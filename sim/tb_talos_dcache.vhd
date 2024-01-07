-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: 4-Way 8KB Non-Blocking L1 Data Cache and MSHR Interface
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_dcache is
end entity tb_talos_dcache;

architecture sim of tb_talos_dcache is

    constant CLK_PERIOD : time := 10 ns;

    signal clk              : std_logic := '0';
    signal rst_n            : std_logic := '0';
    signal flush            : std_logic := '0';

    signal load_req_val     : std_logic := '0';
    signal load_addr        : std_logic_vector(31 downto 0) := (others => '0');
    signal load_hit_val     : std_logic;
    signal load_hit_data    : std_logic_vector(31 downto 0);
    signal load_miss_val    : std_logic;
    signal load_miss_addr   : std_logic_vector(31 downto 0);

    signal refill_wr_val    : std_logic := '0';
    signal refill_wr_addr   : std_logic_vector(31 downto 0) := (others => '0');
    signal refill_wr_data   : std_logic_vector(255 downto 0) := (others => '0');

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_dcache
        generic map (
            SETS        => 64,
            WAYS        => 4,
            INDEX_BITS  => 6,
            OFFSET_BITS => 5,
            TAG_BITS    => 21
        )
        port map (
            clk              => clk,
            rst_n            => rst_n,
            flush            => flush,
            load_req_val     => load_req_val,
            load_addr        => load_addr,
            load_rob_idx     => "00001",
            load_rd_phys     => "100000",
            load_op          => MEM_LW,
            load_hit_val     => load_hit_val,
            load_hit_data    => load_hit_data,
            load_hit_rob_idx => open,
            load_hit_rd_phys => open,
            load_miss_val    => load_miss_val,
            load_miss_addr   => load_miss_addr,
            load_miss_rob    => open,
            load_miss_tag    => open,
            load_miss_op     => open,
            store_commit_val => '0',
            store_commit_adr => (others => '0'),
            store_commit_dat => (others => '0'),
            store_commit_msk => (others => '0'),
            refill_wr_val    => refill_wr_val,
            refill_wr_addr   => refill_wr_addr,
            refill_wr_data   => refill_wr_data,
            evict_wr_val     => open,
            evict_wr_addr    => open,
            evict_wr_data    => open,
            evict_wr_ready   => '1'
        );

    process
    begin
        report "[TEST] Starting tb_talos_dcache verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        -- 1. Refill a cache line at 0x80001000 with known data
        refill_wr_val           <= '1';
        refill_wr_addr          <= x"80001000";
        refill_wr_data(31 downto 0) <= x"12345678"; -- Word at offset 0
        wait until rising_edge(clk);
        refill_wr_val <= '0';
        wait until rising_edge(clk);

        -- 2. Query the cached address: should be an immediate cache hit!
        load_req_val <= '1';
        load_addr    <= x"80001000";
        wait for 1 ns;
        assert load_hit_val = '1' report "Expected cache hit on 0x80001000" severity failure;
        assert load_hit_data = x"12345678" report "Hit data mismatch" severity failure;
        wait until rising_edge(clk);
        load_req_val <= '0';
        wait until rising_edge(clk);

        -- 3. Query an un-cached address: should trigger a cache miss to MSHR!
        load_req_val <= '1';
        load_addr    <= x"80005000";
        wait for 1 ns;
        assert load_miss_val = '1' report "Expected cache miss on 0x80005000" severity failure;
        assert load_miss_addr = x"80005000" report "Miss address mismatch" severity failure;
        wait until rising_edge(clk);
        load_req_val <= '0';
        wait until rising_edge(clk);

        report "[PASS] tb_talos_dcache verification successful.";
        std.env.stop;
    end process;

end architecture sim;
