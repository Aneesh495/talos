-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Memory: 4-Way 8KB Non-Blocking L1 Data Cache with Write-Back
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_dcache is
    generic (
        SETS       : integer := 64;
        WAYS       : integer := 4;
        INDEX_BITS : integer := 6;
        OFFSET_BITS: integer := 5;
        TAG_BITS   : integer := 21
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        flush           : in  std_logic;

        -- Load Query Interface (from LSQ)
        load_req_val    : in  std_logic;
        load_addr       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        load_rob_idx    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        load_rd_phys    : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        load_op         : in  mem_op_t;

        -- Load Hit Response (to CDB)
        load_hit_val    : out std_logic;
        load_hit_data   : out std_logic_vector(XLEN-1 downto 0);
        load_hit_rob_idx: out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        load_hit_rd_phys: out std_logic_vector(PHYS_REG_BITS-1 downto 0);

        -- Load Miss Output (to MSHR)
        load_miss_val   : out std_logic;
        load_miss_addr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        load_miss_rob   : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        load_miss_tag   : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        load_miss_op    : out mem_op_t;

        -- Store Commit Write Interface (from LSQ)
        store_commit_val: in  std_logic;
        store_commit_adr: in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        store_commit_dat: in  std_logic_vector(XLEN-1 downto 0);
        store_commit_msk: in  std_logic_vector(3 downto 0);

        -- MSHR Line Refill Write-Back Ingress
        refill_wr_val   : in  std_logic;
        refill_wr_addr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        refill_wr_data  : in  std_logic_vector(LINE_SIZE_BITS-1 downto 0);

        -- Evicted Dirty Line Write-Back (to AXI4 Master)
        evict_wr_val    : out std_logic;
        evict_wr_addr   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        evict_wr_data   : out std_logic_vector(LINE_SIZE_BITS-1 downto 0);
        evict_wr_ready  : in  std_logic
    );
end entity talos_dcache;

architecture rtl of talos_dcache is

    type line_t is array (0 to 7) of std_logic_vector(31 downto 0);
    type set_data_t is array (0 to WAYS-1) of line_t;
    type cache_data_t is array (0 to SETS-1) of set_data_t;

    type set_tag_t is array (0 to WAYS-1) of std_logic_vector(TAG_BITS-1 downto 0);
    type cache_tag_t is array (0 to SETS-1) of set_tag_t;

    type set_bits_t is array (0 to WAYS-1) of std_logic;
    type cache_bits_t is array (0 to SETS-1) of set_bits_t;
    type array_plru_t is array (0 to SETS-1) of std_logic_vector(2 downto 0);

    signal data_mem   : cache_data_t := (others => (others => (others => (others => '0'))));
    signal tag_mem    : cache_tag_t  := (others => (others => (others => '0')));
    signal valid_mem  : cache_bits_t := (others => (others => '0'));
    signal dirty_mem  : cache_bits_t := (others => (others => '0'));
    signal plru_tree  : array_plru_t := (others => "000");

    -- Load Address Decomposition
    signal ld_idx     : integer range 0 to SETS-1;
    signal ld_tag     : std_logic_vector(TAG_BITS-1 downto 0);
    signal ld_word    : integer range 0 to 7;

    -- Store Address Decomposition
    signal st_idx     : integer range 0 to SETS-1;
    signal st_tag     : std_logic_vector(TAG_BITS-1 downto 0);
    signal st_word    : integer range 0 to 7;

    -- Refill Address Decomposition
    signal rf_idx     : integer range 0 to SETS-1;
    signal rf_tag     : std_logic_vector(TAG_BITS-1 downto 0);

    signal hit_found  : boolean;
    signal hit_way    : integer range 0 to WAYS-1;
    signal hit_data   : std_logic_vector(31 downto 0);

begin

    ld_idx  <= to_integer(unsigned(load_addr(INDEX_BITS+OFFSET_BITS-1 downto OFFSET_BITS)));
    ld_tag  <= load_addr(ADDR_WIDTH-1 downto ADDR_WIDTH-TAG_BITS);
    ld_word <= to_integer(unsigned(load_addr(4 downto 2)));

    st_idx  <= to_integer(unsigned(store_commit_adr(INDEX_BITS+OFFSET_BITS-1 downto OFFSET_BITS)));
    st_tag  <= store_commit_adr(ADDR_WIDTH-1 downto ADDR_WIDTH-TAG_BITS);
    st_word <= to_integer(unsigned(store_commit_adr(4 downto 2)));

    rf_idx  <= to_integer(unsigned(refill_wr_addr(INDEX_BITS+OFFSET_BITS-1 downto OFFSET_BITS)));
    rf_tag  <= refill_wr_addr(ADDR_WIDTH-1 downto ADDR_WIDTH-TAG_BITS);

    -- Combinational 4-way Tag Compare for Load Queries
    process(valid_mem, tag_mem, data_mem, ld_idx, ld_tag, ld_word)
        variable found : boolean;
        variable way   : integer range 0 to WAYS-1;
        variable d     : std_logic_vector(31 downto 0);
    begin
        found := false;
        way   := 0;
        d     := (others => '0');

        for w in 0 to WAYS-1 loop
            if valid_mem(ld_idx)(w) = '1' and tag_mem(ld_idx)(w) = ld_tag and not found then
                found := true;
                way   := w;
                d     := data_mem(ld_idx)(w)(ld_word);
            end if;
        end loop;

        hit_found <= found;
        hit_way   <= way;
        hit_data  <= d;
    end process;

    -- Load Hit / Miss outputs
    process(load_req_val, hit_found, hit_data, load_op, load_rob_idx, load_rd_phys, load_addr)
        variable ext : std_logic_vector(31 downto 0);
    begin
        if load_req_val = '1' and hit_found then
            case load_op is
                when MEM_LB =>
                    ext := (31 downto 8 => hit_data(7)) & hit_data(7 downto 0);
                when MEM_LBU =>
                    ext := (31 downto 8 => '0') & hit_data(7 downto 0);
                when MEM_LH =>
                    ext := (31 downto 16 => hit_data(15)) & hit_data(15 downto 0);
                when MEM_LHU =>
                    ext := (31 downto 16 => '0') & hit_data(15 downto 0);
                when others =>
                    ext := hit_data;
            end case;

            load_hit_val     <= '1';
            load_hit_data    <= ext;
            load_hit_rob_idx <= load_rob_idx;
            load_hit_rd_phys <= load_rd_phys;

            load_miss_val    <= '0';
            load_miss_addr   <= (others => '0');
            load_miss_rob    <= (others => '0');
            load_miss_tag    <= (others => '0');
            load_miss_op     <= MEM_NONE;
        elsif load_req_val = '1' and not hit_found then
            load_hit_val     <= '0';
            load_hit_data    <= (others => '0');
            load_hit_rob_idx <= (others => '0');
            load_hit_rd_phys <= (others => '0');

            -- Trigger non-blocking MSHR allocation
            load_miss_val    <= '1';
            load_miss_addr   <= load_addr;
            load_miss_rob    <= load_rob_idx;
            load_miss_tag    <= load_rd_phys;
            load_miss_op     <= load_op;
        else
            load_hit_val     <= '0';
            load_hit_data    <= (others => '0');
            load_hit_rob_idx <= (others => '0');
            load_hit_rd_phys <= (others => '0');
            load_miss_val    <= '0';
            load_miss_addr   <= (others => '0');
            load_miss_rob    <= (others => '0');
            load_miss_tag    <= (others => '0');
            load_miss_op     <= MEM_NONE;
        end if;
    end process;

    -- Cache Storage Updates (Store Commit, Line Refills, Dirty Evictions)
    process(clk, rst_n)
        variable victim_way : integer range 0 to WAYS-1;
        variable tree       : std_logic_vector(2 downto 0);
        variable evict_line : std_logic_vector(255 downto 0);
    begin
        if rst_n = '0' then
            for s in 0 to SETS-1 loop
                for w in 0 to WAYS-1 loop
                    valid_mem(s)(w) <= '0';
                    dirty_mem(s)(w) <= '0';
                end loop;
                plru_tree(s) <= "000";
            end loop;
            evict_wr_val  <= '0';
            evict_wr_addr <= (others => '0');
            evict_wr_data <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                for s in 0 to SETS-1 loop
                    for w in 0 to WAYS-1 loop
                        valid_mem(s)(w) <= '0';
                        dirty_mem(s)(w) <= '0';
                    end loop;
                end loop;
                evict_wr_val <= '0';
            else
                evict_wr_val <= '0';

                -- 1. APPLY STORE COMMIT (Write-Back into matching line)
                if store_commit_val = '1' then
                    for w in 0 to WAYS-1 loop
                        if valid_mem(st_idx)(w) = '1' and tag_mem(st_idx)(w) = st_tag then
                            for b in 0 to 3 loop
                                if store_commit_msk(b) = '1' then
                                    data_mem(st_idx)(w)(st_word)((b+1)*8-1 downto b*8) <= store_commit_dat((b+1)*8-1 downto b*8);
                                end if;
                            end loop;
                            dirty_mem(st_idx)(w) <= '1';
                        end if;
                    end loop;
                end if;

                -- 2. APPLY REFILLED LINE FROM MSHR
                if refill_wr_val = '1' then
                    tree := plru_tree(rf_idx);
                    -- Determine victim way from Tree-PLRU
                    if tree(0) = '0' then
                        if tree(2) = '0' then victim_way := 3; else victim_way := 2; end if;
                    else
                        if tree(1) = '0' then victim_way := 1; else victim_way := 0; end if;
                    end if;

                    -- If victim is dirty, trigger writeback to memory
                    if valid_mem(rf_idx)(victim_way) = '1' and dirty_mem(rf_idx)(victim_way) = '1' then
                        for i in 0 to 7 loop
                            evict_line((i+1)*32-1 downto i*32) := data_mem(rf_idx)(victim_way)(i);
                        end loop;
                        evict_wr_val  <= '1';
                        evict_wr_addr <= tag_mem(rf_idx)(victim_way) & refill_wr_addr(INDEX_BITS+OFFSET_BITS-1 downto OFFSET_BITS) & "00000";
                        evict_wr_data <= evict_line;
                    end if;

                    -- Unpack incoming 256-bit line into words
                    for i in 0 to 7 loop
                        data_mem(rf_idx)(victim_way)(i) <= refill_wr_data((i+1)*32-1 downto i*32);
                    end loop;
                    tag_mem(rf_idx)(victim_way)   <= rf_tag;
                    valid_mem(rf_idx)(victim_way) <= '1';
                    dirty_mem(rf_idx)(victim_way) <= '0';

                    -- Update PLRU tree
                    case victim_way is
                        when 0 => plru_tree(rf_idx) <= '0' & '0' & tree(2);
                        when 1 => plru_tree(rf_idx) <= '0' & '1' & tree(2);
                        when 2 => plru_tree(rf_idx) <= '1' & tree(1) & '0';
                        when 3 => plru_tree(rf_idx) <= '1' & tree(1) & '1';
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
