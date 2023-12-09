-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Memory: Top-Level Memory Subsystem Integration (LSQ, Store Fwd, MSHR, D-Cache)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_mem_top is
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        flush               : in  std_logic;

        -- Allocation from Dispatch
        alloc_load          : in  std_logic;
        alloc_store         : in  std_logic;
        alloc_rob_idx       : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        alloc_rd_phys       : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alloc_mem_op        : in  mem_op_t;
        lsq_ready           : out std_logic;
        alloc_sq_idx        : out std_logic_vector(SQ_INDEX_BITS-1 downto 0);

        -- Ingress from AGU (Reservation Station)
        agu_val             : in  std_logic;
        agu_is_store        : in  std_logic;
        agu_addr            : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        agu_data            : in  std_logic_vector(XLEN-1 downto 0);
        agu_rob_idx         : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        agu_rd_phys         : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        agu_mem_op          : in  mem_op_t;

        -- In-Order Store Retirement (from ROB)
        commit_store        : in  std_logic;
        commit_rob_idx      : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);

        -- Egress to Common Data Bus
        mem_cdb_val         : out std_logic;
        mem_cdb_tag         : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        mem_cdb_rob_idx     : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        mem_cdb_data        : out std_logic_vector(XLEN-1 downto 0);
        mem_cdb_exc         : out std_logic;
        mem_cdb_exc_cause   : out std_logic_vector(4 downto 0);

        -- Memory Disambiguation Violation Replay to ROB
        mem_order_violation : out std_logic;
        violation_rob_idx   : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);

        -- AXI4 Line Refill Read Channel (from MSHR)
        m_axi_araddr        : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        m_axi_arlen         : out std_logic_vector(7 downto 0);
        m_axi_arsize        : out std_logic_vector(2 downto 0);
        m_axi_arburst       : out std_logic_vector(1 downto 0);
        m_axi_arvalid       : out std_logic;
        m_axi_arready       : in  std_logic;

        m_axi_rdata         : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axi_rresp         : in  std_logic_vector(1 downto 0);
        m_axi_rlast         : in  std_logic;
        m_axi_rvalid        : in  std_logic;
        m_axi_rready        : out std_logic;

        -- AXI4 Dirty Line Eviction Write Channel (from D-Cache)
        m_axi_awaddr        : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        m_axi_awlen         : out std_logic_vector(7 downto 0);
        m_axi_awsize        : out std_logic_vector(2 downto 0);
        m_axi_awburst       : out std_logic_vector(1 downto 0);
        m_axi_awvalid       : out std_logic;
        m_axi_awready       : in  std_logic;

        m_axi_wdata         : out std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axi_wstrb         : out std_logic_vector(3 downto 0);
        m_axi_wlast         : out std_logic;
        m_axi_wvalid        : out std_logic;
        m_axi_wready        : in  std_logic;

        m_axi_bvalid        : in  std_logic;
        m_axi_bready        : out std_logic
    );
end entity talos_mem_top;

architecture rtl of talos_mem_top is

    -- LSQ to D-Cache signals
    signal lsq_dcache_req_val : std_logic;
    signal lsq_dcache_req_adr : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal lsq_dcache_req_rob : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal lsq_dcache_req_tag : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal lsq_dcache_req_op  : mem_op_t;

    signal lsq_commit_wr_val  : std_logic;
    signal lsq_commit_wr_adr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal lsq_commit_wr_dat  : std_logic_vector(XLEN-1 downto 0);
    signal lsq_commit_wr_msk  : std_logic_vector(3 downto 0);

    signal lsq_fwd_val        : std_logic;
    signal lsq_fwd_tag        : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal lsq_fwd_rob        : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal lsq_fwd_dat        : std_logic_vector(XLEN-1 downto 0);

    -- D-Cache to MSHR signals
    signal dcache_hit_val     : std_logic;
    signal dcache_hit_data    : std_logic_vector(XLEN-1 downto 0);
    signal dcache_hit_rob     : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal dcache_hit_tag     : std_logic_vector(PHYS_REG_BITS-1 downto 0);

    signal dcache_miss_val    : std_logic;
    signal dcache_miss_adr    : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal dcache_miss_rob    : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal dcache_miss_tag    : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal dcache_miss_op     : mem_op_t;

    -- MSHR signals
    signal mshr_axi_req_val   : std_logic;
    signal mshr_axi_req_addr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal mshr_axi_req_id    : std_logic_vector(1 downto 0);

    signal mshr_refill_done   : std_logic;
    signal mshr_refill_id     : std_logic_vector(1 downto 0);
    signal mshr_refill_data   : std_logic_vector(255 downto 0);

    signal mshr_cdb_val       : std_logic;
    signal mshr_cdb_tag       : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal mshr_cdb_rob       : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal mshr_cdb_data      : std_logic_vector(XLEN-1 downto 0);

    signal mshr_cache_wr_val  : std_logic;
    signal mshr_cache_wr_addr : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal mshr_cache_wr_data : std_logic_vector(255 downto 0);

    -- D-Cache eviction signals
    signal dcache_evict_val   : std_logic;
    signal dcache_evict_addr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal dcache_evict_data  : std_logic_vector(255 downto 0);

    -- AXI Read assembly buffer
    signal r_beat_cnt         : integer range 0 to 7 := 0;
    signal r_line_buf         : std_logic_vector(255 downto 0) := (others => '0');

begin

    -- 1. Load-Store Queue (LSQ)
    u_lsq : entity work.talos_lsq
        port map (
            clk                 => clk,
            rst_n               => rst_n,
            flush               => flush,
            alloc_load          => alloc_load,
            alloc_store         => alloc_store,
            alloc_rob_idx       => alloc_rob_idx,
            alloc_rd_phys       => alloc_rd_phys,
            alloc_mem_op        => alloc_mem_op,
            lsq_ready           => lsq_ready,
            alloc_sq_idx        => alloc_sq_idx,
            agu_val             => agu_val,
            agu_is_store        => agu_is_store,
            agu_addr            => agu_addr,
            agu_data            => agu_data,
            agu_rob_idx         => agu_rob_idx,
            agu_rd_phys         => agu_rd_phys,
            agu_mem_op          => agu_mem_op,
            dcache_req_val      => lsq_dcache_req_val,
            dcache_req_addr     => lsq_dcache_req_adr,
            dcache_req_rob_idx  => lsq_dcache_req_rob,
            dcache_req_rd_phys  => lsq_dcache_req_tag,
            dcache_req_op       => lsq_dcache_req_op,
            commit_store        => commit_store,
            commit_rob_idx      => commit_rob_idx,
            dcache_wr_val       => lsq_commit_wr_val,
            dcache_wr_addr      => lsq_commit_wr_adr,
            dcache_wr_data      => lsq_commit_wr_dat,
            dcache_wr_mask      => lsq_commit_wr_msk,
            fwd_cdb_val         => lsq_fwd_val,
            fwd_cdb_tag         => lsq_fwd_tag,
            fwd_cdb_rob_idx     => lsq_fwd_rob,
            fwd_cdb_data        => lsq_fwd_dat,
            mem_order_violation => mem_order_violation,
            violation_rob_idx   => violation_rob_idx
        );

    -- 2. L1 Data Cache
    u_dcache : entity work.talos_dcache
        port map (
            clk              => clk,
            rst_n            => rst_n,
            flush            => flush,
            load_req_val     => lsq_dcache_req_val,
            load_addr        => lsq_dcache_req_adr,
            load_rob_idx     => lsq_dcache_req_rob,
            load_rd_phys     => lsq_dcache_req_tag,
            load_op          => lsq_dcache_req_op,
            load_hit_val     => dcache_hit_val,
            load_hit_data    => dcache_hit_data,
            load_hit_rob_idx => dcache_hit_rob,
            load_hit_rd_phys => dcache_hit_tag,
            load_miss_val    => dcache_miss_val,
            load_miss_addr   => dcache_miss_adr,
            load_miss_rob    => dcache_miss_rob,
            load_miss_tag    => dcache_miss_tag,
            load_miss_op     => dcache_miss_op,
            store_commit_val => lsq_commit_wr_val,
            store_commit_adr => lsq_commit_wr_adr,
            store_commit_dat => lsq_commit_wr_dat,
            store_commit_msk => lsq_commit_wr_msk,
            refill_wr_val    => mshr_cache_wr_val,
            refill_wr_addr   => mshr_cache_wr_addr,
            refill_wr_data   => mshr_cache_wr_data,
            evict_wr_val     => dcache_evict_val,
            evict_wr_addr    => dcache_evict_addr,
            evict_wr_data    => dcache_evict_data,
            evict_wr_ready   => m_axi_awready
        );

    -- 3. Miss Status Holding Register (MSHR) Controller
    u_mshr : entity work.talos_mshr
        port map (
            clk             => clk,
            rst_n           => rst_n,
            flush           => flush,
            alloc_val       => dcache_miss_val,
            alloc_addr      => dcache_miss_adr,
            alloc_rob_idx   => dcache_miss_rob,
            alloc_rd_phys   => dcache_miss_tag,
            alloc_op        => dcache_miss_op,
            mshr_full       => open,
            mshr_merged     => open,
            alloc_idx_out   => open,
            axi_req_val     => mshr_axi_req_val,
            axi_req_addr    => mshr_axi_req_addr,
            axi_req_mshr_id => mshr_axi_req_id,
            axi_req_ready   => m_axi_arready,
            refill_done_val => mshr_refill_done,
            refill_mshr_id  => mshr_refill_id,
            refill_data     => mshr_refill_data,
            cdb_val         => mshr_cdb_val,
            cdb_tag         => mshr_cdb_tag,
            cdb_rob_idx     => mshr_cdb_rob,
            cdb_data        => mshr_cdb_data,
            cache_wr_val    => mshr_cache_wr_val,
            cache_wr_addr   => mshr_cache_wr_addr,
            cache_wr_data   => mshr_cache_wr_data
        );

    -- Multiplex CDB Load output: LSQ store forward, Cache hit, or MSHR refill
    process(lsq_fwd_val, lsq_fwd_tag, lsq_fwd_rob, lsq_fwd_dat,
            dcache_hit_val, dcache_hit_tag, dcache_hit_rob, dcache_hit_data,
            mshr_cdb_val, mshr_cdb_tag, mshr_cdb_rob, mshr_cdb_data)
    begin
        mem_cdb_exc       <= '0';
        mem_cdb_exc_cause <= (others => '0');

        if lsq_fwd_val = '1' then
            mem_cdb_val     <= '1';
            mem_cdb_tag     <= lsq_fwd_tag;
            mem_cdb_rob_idx <= lsq_fwd_rob;
            mem_cdb_data    <= lsq_fwd_dat;
        elsif dcache_hit_val = '1' then
            mem_cdb_val     <= '1';
            mem_cdb_tag     <= dcache_hit_tag;
            mem_cdb_rob_idx <= dcache_hit_rob;
            mem_cdb_data    <= dcache_hit_data;
        elsif mshr_cdb_val = '1' then
            mem_cdb_val     <= '1';
            mem_cdb_tag     <= mshr_cdb_tag;
            mem_cdb_rob_idx <= mshr_cdb_rob;
            mem_cdb_data    <= mshr_cdb_data;
        else
            mem_cdb_val     <= '0';
            mem_cdb_tag     <= (others => '0');
            mem_cdb_rob_idx <= (others => '0');
            mem_cdb_data    <= (others => '0');
        end if;
    end process;

    -- AXI4 Read Channel Assignment
    m_axi_araddr  <= mshr_axi_req_addr;
    m_axi_arlen   <= x"07"; -- 8 beats of 32 bits = 256-bit line
    m_axi_arsize  <= "010"; -- 4 bytes per beat
    m_axi_arburst <= AXI4_BURST_INCR;
    m_axi_arvalid <= mshr_axi_req_val;
    m_axi_rready  <= '1';

    -- AXI4 Read Beat Reassembly into 256-bit line
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            r_beat_cnt       <= 0;
            r_line_buf       <= (others => '0');
            mshr_refill_done <= '0';
            mshr_refill_id   <= (others => '0');
            mshr_refill_data <= (others => '0');
        elsif rising_edge(clk) then
            mshr_refill_done <= '0';
            if m_axi_rvalid = '1' then
                r_line_buf((r_beat_cnt+1)*32-1 downto r_beat_cnt*32) <= m_axi_rdata;
                if r_beat_cnt = 7 or m_axi_rlast = '1' then
                    mshr_refill_done <= '1';
                    mshr_refill_id   <= mshr_axi_req_id;
                    mshr_refill_data <= r_line_buf(223 downto 0) & m_axi_rdata;
                    r_beat_cnt       <= 0;
                else
                    r_beat_cnt <= r_beat_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- AXI4 Write Channel Assignment for Cache Evictions
    m_axi_awaddr  <= dcache_evict_addr;
    m_axi_awlen   <= x"07";
    m_axi_awsize  <= "010";
    m_axi_awburst <= AXI4_BURST_INCR;
    m_axi_awvalid <= dcache_evict_val;
    m_axi_wdata   <= dcache_evict_data(31 downto 0);
    m_axi_wstrb   <= "1111";
    m_axi_wlast   <= '1';
    m_axi_wvalid  <= dcache_evict_val;
    m_axi_bready  <= '1';

end architecture rtl;
