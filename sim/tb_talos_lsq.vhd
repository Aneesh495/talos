-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Load-Store Queue and Speculative Store-to-Load Forwarding
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_lsq is
end entity tb_talos_lsq;

architecture sim of tb_talos_lsq is

    constant CLK_PERIOD : time := 10 ns;

    signal clk                 : std_logic := '0';
    signal rst_n               : std_logic := '0';
    signal flush               : std_logic := '0';

    signal alloc_load          : std_logic := '0';
    signal alloc_store         : std_logic := '0';
    signal alloc_rob_idx       : std_logic_vector(4 downto 0) := "00001";
    signal alloc_rd_phys       : std_logic_vector(5 downto 0) := "100000";
    signal alloc_mem_op        : mem_op_t := MEM_SW;
    signal lsq_ready           : std_logic;

    signal agu_val             : std_logic := '0';
    signal agu_is_store        : std_logic := '0';
    signal agu_addr            : std_logic_vector(31 downto 0) := (others => '0');
    signal agu_data            : std_logic_vector(31 downto 0) := (others => '0');
    signal agu_rob_idx         : std_logic_vector(4 downto 0) := (others => '0');
    signal agu_rd_phys         : std_logic_vector(5 downto 0) := (others => '0');
    signal agu_mem_op          : mem_op_t := MEM_SW;

    signal dcache_req_val      : std_logic;
    signal dcache_wr_val       : std_logic;
    signal dcache_wr_addr      : std_logic_vector(31 downto 0);
    signal dcache_wr_data      : std_logic_vector(31 downto 0);

    signal fwd_cdb_val         : std_logic;
    signal fwd_cdb_tag         : std_logic_vector(5 downto 0);
    signal fwd_cdb_rob_idx     : std_logic_vector(4 downto 0);
    signal fwd_cdb_data        : std_logic_vector(31 downto 0);

    signal commit_store        : std_logic := '0';
    signal commit_rob_idx      : std_logic_vector(4 downto 0) := (others => '0');

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_lsq
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
            alloc_sq_idx        => open,
            agu_val             => agu_val,
            agu_is_store        => agu_is_store,
            agu_addr            => agu_addr,
            agu_data            => agu_data,
            agu_rob_idx         => agu_rob_idx,
            agu_rd_phys         => agu_rd_phys,
            agu_mem_op          => agu_mem_op,
            dcache_req_val      => dcache_req_val,
            dcache_req_addr     => open,
            dcache_req_rob_idx  => open,
            dcache_req_rd_phys  => open,
            dcache_req_op       => open,
            commit_store        => commit_store,
            commit_rob_idx      => commit_rob_idx,
            dcache_wr_val       => dcache_wr_val,
            dcache_wr_addr      => dcache_wr_addr,
            dcache_wr_data      => dcache_wr_data,
            dcache_wr_mask      => open,
            fwd_cdb_val         => fwd_cdb_val,
            fwd_cdb_tag         => fwd_cdb_tag,
            fwd_cdb_rob_idx     => fwd_cdb_rob_idx,
            fwd_cdb_data        => fwd_cdb_data,
            mem_order_violation => open,
            violation_rob_idx   => open
        );

    process
    begin
        report "[TEST] Starting tb_talos_lsq verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert lsq_ready = '1' report "LSQ should be ready on reset" severity failure;

        -- 1. Allocate a Store instruction: sw at 0x80002000, data 0xCAFEBABE (rob_idx 1)
        alloc_store   <= '1';
        alloc_rob_idx <= "00001";
        alloc_mem_op  <= MEM_SW;
        wait until rising_edge(clk);
        alloc_store   <= '0';

        -- Execute Store AGU
        agu_val      <= '1';
        agu_is_store <= '1';
        agu_addr     <= x"80002000";
        agu_data     <= x"CAFEBABE";
        agu_rob_idx  <= "00001";
        agu_mem_op   <= MEM_SW;
        wait until rising_edge(clk);
        agu_val      <= '0';

        -- 2. Allocate and Execute a matching Load: lw at 0x80002000 (rob_idx 2, rd_phys 35)
        alloc_load    <= '1';
        alloc_rob_idx <= "00010";
        alloc_rd_phys <= "100011"; -- tag 35
        alloc_mem_op  <= MEM_LW;
        wait until rising_edge(clk);
        alloc_load    <= '0';

        -- Execute Load AGU
        agu_val      <= '1';
        agu_is_store <= '0';
        agu_addr     <= x"80002000";
        agu_rob_idx  <= "00010";
        agu_rd_phys  <= "100011";
        agu_mem_op   <= MEM_LW;
        wait until rising_edge(clk);
        agu_val      <= '0';

        -- 3. Verify Speculative Store-to-Load Forwarding on CDB!
        wait for 1 ns;
        assert fwd_cdb_val = '1' report "Store-to-load forwarding was not triggered" severity failure;
        assert fwd_cdb_data = x"CAFEBABE" report "Forwarded data mismatch" severity failure;
        assert fwd_cdb_tag = "100011" report "Forwarded tag mismatch" severity failure;

        -- 4. Commit Store instruction from ROB
        commit_store   <= '1';
        commit_rob_idx <= "00001";
        wait until rising_edge(clk);
        commit_store   <= '0';

        wait for 1 ns;
        assert dcache_wr_val = '1' report "Committed store should write to D-Cache" severity failure;
        assert dcache_wr_data = x"CAFEBABE" report "D-Cache write data mismatch" severity failure;
        assert dcache_wr_addr = x"80002000" report "D-Cache write address mismatch" severity failure;

        wait until rising_edge(clk);

        report "[PASS] tb_talos_lsq verification successful.";
        std.env.stop;
    end process;

end architecture sim;
