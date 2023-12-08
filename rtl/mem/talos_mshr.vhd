-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Memory: 4-Entry Miss Status Holding Register (MSHR) Non-Blocking Controller
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_mshr is
    generic (
        DEPTH      : integer := MSHR_DEPTH; -- 4 entries
        INDEX_BITS : integer := MSHR_INDEX_BITS
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        flush           : in  std_logic;

        -- Allocation Interface from L1 D-Cache (on Cache Miss)
        alloc_val       : in  std_logic;
        alloc_addr      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        alloc_rob_idx   : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        alloc_rd_phys   : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alloc_op        : in  mem_op_t;

        mshr_full       : out std_logic;
        mshr_merged     : out std_logic;
        alloc_idx_out   : out std_logic_vector(INDEX_BITS-1 downto 0);

        -- Memory Refill Dispatch (to AXI4 Master)
        axi_req_val     : out std_logic;
        axi_req_addr    : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        axi_req_mshr_id : out std_logic_vector(INDEX_BITS-1 downto 0);
        axi_req_ready   : in  std_logic;

        -- Memory Refill Completion (from AXI4 Master)
        refill_done_val : in  std_logic;
        refill_mshr_id  : in  std_logic_vector(INDEX_BITS-1 downto 0);
        refill_data     : in  std_logic_vector(LINE_SIZE_BITS-1 downto 0);

        -- CDB Broadcast for Pending Load Targets
        cdb_val         : out std_logic;
        cdb_tag         : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        cdb_rob_idx     : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        cdb_data        : out std_logic_vector(XLEN-1 downto 0);

        -- D-Cache Line Write-Back Interface
        cache_wr_val    : out std_logic;
        cache_wr_addr   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        cache_wr_data   : out std_logic_vector(LINE_SIZE_BITS-1 downto 0)
    );
end entity talos_mshr;

architecture rtl of talos_mshr is

    type mshr_entry_t is record
        valid       : std_logic;
        dispatched  : std_logic; -- Sent to AXI4 bus
        line_addr   : std_logic_vector(ADDR_WIDTH-1 downto 5);
        word_offset : std_logic_vector(2 downto 0);
        rob_idx     : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys     : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        mem_op      : mem_op_t;
    end record mshr_entry_t;

    type mshr_array_t is array (0 to DEPTH-1) of mshr_entry_t;
    signal entries : mshr_array_t := (others => (
        valid       => '0',
        dispatched  => '0',
        line_addr   => (others => '0'),
        word_offset => (others => '0'),
        rob_idx     => (others => '0'),
        rd_phys     => (others => '0'),
        mem_op      => MEM_NONE
    ));

    signal free_id_found : boolean;
    signal free_id_idx   : integer range 0 to DEPTH-1;

    signal merge_found   : boolean;
    signal merge_idx     : integer range 0 to DEPTH-1;

begin

    -- Free slot search & Primary Miss vs Secondary Miss detection
    process(entries, alloc_addr)
        variable f_free : boolean;
        variable i_free : integer range 0 to DEPTH-1;
        variable f_merg : boolean;
        variable i_merg : integer range 0 to DEPTH-1;
    begin
        f_free := false;
        i_free := 0;
        f_merg := false;
        i_merg := 0;

        for i in 0 to DEPTH-1 loop
            if entries(i).valid = '0' and not f_free then
                i_free := i;
                f_free := true;
            elsif entries(i).valid = '1' and entries(i).line_addr = alloc_addr(ADDR_WIDTH-1 downto 5) and not f_merg then
                i_merg := i;
                f_merg := true;
            end if;
        end loop;

        free_id_found <= f_free;
        free_id_idx   <= i_free;
        merge_found   <= f_merg;
        merge_idx     <= i_merg;
    end process;

    mshr_full     <= bool_to_sl(not free_id_found and not merge_found);
    mshr_merged   <= bool_to_sl(merge_found);
    alloc_idx_out <= std_logic_vector(to_unsigned(merge_idx, INDEX_BITS)) when merge_found else
                     std_logic_vector(to_unsigned(free_id_idx, INDEX_BITS));

    -- Search for pending undispatched entries to send to AXI4 Master
    process(entries)
        variable f   : boolean;
        variable idx : integer range 0 to DEPTH-1;
    begin
        f   := false;
        idx := 0;
        for i in 0 to DEPTH-1 loop
            if entries(i).valid = '1' and entries(i).dispatched = '0' and not f then
                idx := i;
                f   := true;
            end if;
        end loop;

        axi_req_val     <= bool_to_sl(f);
        axi_req_mshr_id <= std_logic_vector(to_unsigned(idx, INDEX_BITS));
        axi_req_addr    <= entries(idx).line_addr & "00000";
    end process;

    -- MSHR State Machine and Refill Handler
    process(clk, rst_n)
        variable ref_idx  : integer range 0 to DEPTH-1;
        variable w_off    : integer range 0 to 7;
        variable word32   : std_logic_vector(31 downto 0);
        variable ext_data : std_logic_vector(31 downto 0);
    begin
        if rst_n = '0' then
            for i in 0 to DEPTH-1 loop
                entries(i).valid      <= '0';
                entries(i).dispatched <= '0';
            end loop;
            cdb_val      <= '0';
            cdb_tag      <= (others => '0');
            cdb_rob_idx  <= (others => '0');
            cdb_data     <= (others => '0');
            cache_wr_val <= '0';
            cache_wr_addr<= (others => '0');
            cache_wr_data<= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                for i in 0 to DEPTH-1 loop
                    entries(i).valid <= '0';
                end loop;
                cdb_val      <= '0';
                cache_wr_val <= '0';
            else
                cdb_val      <= '0';
                cache_wr_val <= '0';

                -- Mark dispatched when AXI accepts
                for i in 0 to DEPTH-1 loop
                    if entries(i).valid = '1' and entries(i).dispatched = '0' and axi_req_ready = '1' then
                        entries(i).dispatched <= '1';
                        exit;
                    end if;
                end loop;

                -- Allocate incoming miss
                if alloc_val = '1' and free_id_found and not merge_found then
                    entries(free_id_idx).valid       <= '1';
                    entries(free_id_idx).dispatched  <= '0';
                    entries(free_id_idx).line_addr   <= alloc_addr(ADDR_WIDTH-1 downto 5);
                    entries(free_id_idx).word_offset <= alloc_addr(4 downto 2);
                    entries(free_id_idx).rob_idx     <= alloc_rob_idx;
                    entries(free_id_idx).rd_phys     <= alloc_rd_phys;
                    entries(free_id_idx).mem_op      <= alloc_op;
                end if;

                -- Handle Completed Refill from AXI4
                if refill_done_val = '1' then
                    ref_idx := to_integer(unsigned(refill_mshr_id));

                    if entries(ref_idx).valid = '1' then
                        -- Extract requested 32-bit word from the 256-bit cache line
                        w_off  := to_integer(unsigned(entries(ref_idx).word_offset));
                        word32 := refill_data((w_off+1)*32-1 downto w_off*32);

                        -- Sign-extension / formatting based on mem_op
                        case entries(ref_idx).mem_op is
                            when MEM_LB =>
                                ext_data := (31 downto 8 => word32(7)) & word32(7 downto 0);
                            when MEM_LBU =>
                                ext_data := (31 downto 8 => '0') & word32(7 downto 0);
                            when MEM_LH =>
                                ext_data := (31 downto 16 => word32(15)) & word32(15 downto 0);
                            when MEM_LHU =>
                                ext_data := (31 downto 16 => '0') & word32(15 downto 0);
                            when others =>
                                ext_data := word32;
                        end case;

                        -- Broadcast on CDB
                        cdb_val     <= '1';
                        cdb_tag     <= entries(ref_idx).rd_phys;
                        cdb_rob_idx <= entries(ref_idx).rob_idx;
                        cdb_data    <= ext_data;

                        -- Write refilled 256-bit line into L1 D-Cache
                        cache_wr_val  <= '1';
                        cache_wr_addr <= entries(ref_idx).line_addr & "00000";
                        cache_wr_data <= refill_data;

                        -- Free MSHR slot
                        entries(ref_idx).valid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
