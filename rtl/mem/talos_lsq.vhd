-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Memory: 16-Entry Combined Load Queue and Store Queue (LSQ)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_lsq is
    generic (
        LQ_ENTRIES : integer := LQ_DEPTH; -- 16
        SQ_ENTRIES : integer := SQ_DEPTH  -- 16
    );
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        flush               : in  std_logic;

        -- Allocation Interface from Dispatch
        alloc_load          : in  std_logic;
        alloc_store         : in  std_logic;
        alloc_rob_idx       : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        alloc_rd_phys       : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alloc_mem_op        : in  mem_op_t;
        lsq_ready           : out std_logic;
        alloc_sq_idx        : out std_logic_vector(SQ_INDEX_BITS-1 downto 0);

        -- Address Generation Unit (AGU) Ingress
        agu_val             : in  std_logic;
        agu_is_store        : in  std_logic;
        agu_addr            : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        agu_data            : in  std_logic_vector(XLEN-1 downto 0);
        agu_rob_idx         : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        agu_rd_phys         : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        agu_mem_op          : in  mem_op_t;

        -- L1 Data Cache Query Interface (for Loads)
        dcache_req_val      : out std_logic;
        dcache_req_addr     : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        dcache_req_rob_idx  : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        dcache_req_rd_phys  : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        dcache_req_op       : out mem_op_t;

        -- In-Order Store Retirement Interface (from ROB Commit)
        commit_store        : in  std_logic;
        commit_rob_idx      : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);

        -- L1 Data Cache Write Interface (Retired Stores)
        dcache_wr_val       : out std_logic;
        dcache_wr_addr      : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        dcache_wr_data      : out std_logic_vector(XLEN-1 downto 0);
        dcache_wr_mask      : out std_logic_vector(3 downto 0);

        -- Speculative Forwarding & Violation Output to CDB
        fwd_cdb_val         : out std_logic;
        fwd_cdb_tag         : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        fwd_cdb_rob_idx     : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        fwd_cdb_data        : out std_logic_vector(XLEN-1 downto 0);

        -- Memory Disambiguation Violation Replay
        mem_order_violation : out std_logic;
        violation_rob_idx   : out std_logic_vector(ROB_INDEX_BITS-1 downto 0)
    );
end entity talos_lsq;

architecture rtl of talos_lsq is

    type sq_entry_t is record
        valid       : std_logic;
        addr_valid  : std_logic;
        data_valid  : std_logic;
        addr        : std_logic_vector(ADDR_WIDTH-1 downto 0);
        data        : std_logic_vector(XLEN-1 downto 0);
        byte_mask   : std_logic_vector(3 downto 0);
        rob_idx     : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        committed   : std_logic;
    end record sq_entry_t;

    type sq_array_t is array (0 to SQ_ENTRIES-1) of sq_entry_t;
    signal sq : sq_array_t := (others => (
        valid       => '0',
        addr_valid  => '0',
        data_valid  => '0',
        addr        => (others => '0'),
        data        => (others => '0'),
        byte_mask   => (others => '0'),
        rob_idx     => (others => '0'),
        committed   => '0'
    ));

    type lq_entry_t is record
        valid       : std_logic;
        addr_valid  : std_logic;
        addr        : std_logic_vector(ADDR_WIDTH-1 downto 0);
        rob_idx     : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys     : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        mem_op      : mem_op_t;
        executed    : std_logic;
    end record lq_entry_t;

    type lq_array_t is array (0 to LQ_ENTRIES-1) of lq_entry_t;
    signal lq : lq_array_t := (others => (
        valid       => '0',
        addr_valid  => '0',
        addr        => (others => '0'),
        rob_idx     => (others => '0'),
        rd_phys     => (others => '0'),
        mem_op      => MEM_NONE,
        executed    => '0'
    ));

    signal sq_free_idx : integer range 0 to SQ_ENTRIES-1 := 0;
    signal sq_has_free : boolean := true;

    signal lq_free_idx : integer range 0 to LQ_ENTRIES-1 := 0;
    signal lq_has_free : boolean := true;

begin

    -- Free entry search
    process(sq)
        variable found : boolean;
        variable idx   : integer range 0 to SQ_ENTRIES-1;
    begin
        found := false;
        idx   := 0;
        for i in 0 to SQ_ENTRIES-1 loop
            if sq(i).valid = '0' and not found then
                idx   := i;
                found := true;
            end if;
        end loop;
        sq_has_free <= found;
        sq_free_idx <= idx;
    end process;

    process(lq)
        variable found : boolean;
        variable idx   : integer range 0 to LQ_ENTRIES-1;
    begin
        found := false;
        idx   := 0;
        for i in 0 to LQ_ENTRIES-1 loop
            if lq(i).valid = '0' and not found then
                idx   := i;
                found := true;
            end if;
        end loop;
        lq_has_free <= found;
        lq_free_idx <= idx;
    end process;

    lsq_ready    <= bool_to_sl(sq_has_free and lq_has_free);
    alloc_sq_idx <= std_logic_vector(to_unsigned(sq_free_idx, SQ_INDEX_BITS));

    -- Load / Store Queue Management and Execution Process
    process(clk, rst_n)
        variable fwd_found : boolean;
        variable fwd_data  : std_logic_vector(XLEN-1 downto 0);
        variable mask_calc : std_logic_vector(3 downto 0);
        variable offset    : integer range 0 to 3;
    begin
        if rst_n = '0' then
            for i in 0 to SQ_ENTRIES-1 loop
                sq(i).valid <= '0';
            end loop;
            for i in 0 to LQ_ENTRIES-1 loop
                lq(i).valid <= '0';
            end loop;
            dcache_req_val      <= '0';
            dcache_req_addr     <= (others => '0');
            dcache_req_rob_idx  <= (others => '0');
            dcache_req_rd_phys  <= (others => '0');
            dcache_req_op       <= MEM_NONE;
            dcache_wr_val       <= '0';
            dcache_wr_addr      <= (others => '0');
            dcache_wr_data      <= (others => '0');
            dcache_wr_mask      <= (others => '0');
            fwd_cdb_val         <= '0';
            fwd_cdb_tag         <= (others => '0');
            fwd_cdb_rob_idx     <= (others => '0');
            fwd_cdb_data        <= (others => '0');
            mem_order_violation <= '0';
            violation_rob_idx   <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                for i in 0 to SQ_ENTRIES-1 loop
                    if sq(i).committed = '0' then
                        sq(i).valid <= '0';
                    end if;
                end loop;
                for i in 0 to LQ_ENTRIES-1 loop
                    lq(i).valid <= '0';
                end loop;
                dcache_req_val      <= '0';
                dcache_wr_val       <= '0';
                fwd_cdb_val         <= '0';
                mem_order_violation <= '0';
            else
                dcache_req_val      <= '0';
                dcache_wr_val       <= '0';
                fwd_cdb_val         <= '0';
                mem_order_violation <= '0';

                -- 1. ALLOCATION FROM DISPATCH
                if alloc_store = '1' and sq_has_free then
                    sq(sq_free_idx).valid      <= '1';
                    sq(sq_free_idx).addr_valid <= '0';
                    sq(sq_free_idx).data_valid <= '0';
                    sq(sq_free_idx).rob_idx    <= alloc_rob_idx;
                    sq(sq_free_idx).committed  <= '0';
                end if;

                if alloc_load = '1' and lq_has_free then
                    lq(lq_free_idx).valid      <= '1';
                    lq(lq_free_idx).addr_valid <= '0';
                    lq(lq_free_idx).rob_idx    <= alloc_rob_idx;
                    lq(lq_free_idx).rd_phys    <= alloc_rd_phys;
                    lq(lq_free_idx).mem_op     <= alloc_mem_op;
                    lq(lq_free_idx).executed   <= '0';
                end if;

                -- 2. ADDRESS GENERATION (AGU) EXECUTION
                if agu_val = '1' then
                    offset := to_integer(unsigned(agu_addr(1 downto 0)));

                    case agu_mem_op is
                        when MEM_SB =>
                            mask_calc := (others => '0');
                            mask_calc(offset) := '1';
                        when MEM_SH =>
                            if offset = 0 then
                                mask_calc := "0011";
                            else
                                mask_calc := "1100";
                            end if;
                        when MEM_SW =>
                            mask_calc := "1111";
                        when others =>
                            mask_calc := "1111";
                    end case;

                    if agu_is_store = '1' then
                        -- Update Store Queue
                        for i in 0 to SQ_ENTRIES-1 loop
                            if sq(i).valid = '1' and sq(i).rob_idx = agu_rob_idx then
                                sq(i).addr_valid <= '1';
                                sq(i).data_valid <= '1';
                                sq(i).addr       <= agu_addr;
                                sq(i).data       <= agu_data;
                                sq(i).byte_mask  <= mask_calc;
                            end if;
                        end loop;

                        -- Check for Memory Order Violation against younger already-executed loads
                        for j in 0 to LQ_ENTRIES-1 loop
                            if lq(j).valid = '1' and lq(j).executed = '1' and lq(j).addr = agu_addr then
                                if unsigned(lq(j).rob_idx) > unsigned(agu_rob_idx) then
                                    mem_order_violation <= '1';
                                    violation_rob_idx   <= lq(j).rob_idx;
                                end if;
                            end if;
                        end loop;

                    else
                        -- Load Execution: Check Store-to-Load Forwarding in SQ
                        fwd_found := false;
                        fwd_data  := (others => '0');

                        for i in SQ_ENTRIES-1 downto 0 loop
                            if sq(i).valid = '1' and sq(i).addr_valid = '1' and sq(i).data_valid = '1' then
                                if sq(i).addr = agu_addr and not fwd_found then
                                    fwd_found := true;
                                    fwd_data  := sq(i).data;
                                end if;
                            end if;
                        end loop;

                        -- Update LQ entry
                        for j in 0 to LQ_ENTRIES-1 loop
                            if lq(j).valid = '1' and lq(j).rob_idx = agu_rob_idx then
                                lq(j).addr_valid <= '1';
                                lq(j).addr       <= agu_addr;
                                lq(j).executed   <= '1';
                            end if;
                        end loop;

                        if fwd_found then
                            -- Forward directly to CDB
                            fwd_cdb_val     <= '1';
                            fwd_cdb_tag     <= agu_rd_phys;
                            fwd_cdb_rob_idx <= agu_rob_idx;
                            fwd_cdb_data    <= fwd_data;
                        else
                            -- Issue read query to L1 Data Cache
                            dcache_req_val     <= '1';
                            dcache_req_addr    <= agu_addr;
                            dcache_req_rob_idx <= agu_rob_idx;
                            dcache_req_rd_phys <= agu_rd_phys;
                            dcache_req_op      <= agu_mem_op;
                        end if;
                    end if;
                end if;

                -- 3. IN-ORDER STORE RETIREMENT TO D-CACHE
                if commit_store = '1' then
                    for i in 0 to SQ_ENTRIES-1 loop
                        if sq(i).valid = '1' and sq(i).rob_idx = commit_rob_idx then
                            dcache_wr_val  <= '1';
                            dcache_wr_addr <= sq(i).addr;
                            dcache_wr_data <= sq(i).data;
                            dcache_wr_mask <= sq(i).byte_mask;
                            sq(i).valid    <= '0'; -- Retired and freed
                        end if;
                    end loop;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
