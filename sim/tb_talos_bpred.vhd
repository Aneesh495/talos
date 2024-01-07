-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Branch Predictor (Gshare), BTB, and Return Address Stack (RAS)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_bpred is
end entity tb_talos_bpred;

architecture sim of tb_talos_bpred is

    constant CLK_PERIOD : time := 10 ns;

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    -- Gshare signals
    signal gshare_fetch_pc    : std_logic_vector(31 downto 0) := (others => '0');
    signal gshare_pred_taken  : std_logic;
    signal gshare_spec_ghr    : std_logic_vector(9 downto 0);
    signal gshare_advance     : std_logic := '0';
    signal gshare_resolve_val : std_logic := '0';
    signal gshare_resolve_pc  : std_logic_vector(31 downto 0) := (others => '0');
    signal gshare_resolve_ghr : std_logic_vector(9 downto 0) := (others => '0');
    signal gshare_resolve_tkn : std_logic := '0';
    signal gshare_resolve_mis : std_logic := '0';

    -- BTB signals
    signal btb_fetch_pc   : std_logic_vector(31 downto 0) := (others => '0');
    signal btb_hit        : std_logic;
    signal btb_target_pc  : std_logic_vector(31 downto 0);
    signal btb_update_val : std_logic := '0';
    signal btb_update_pc  : std_logic_vector(31 downto 0) := (others => '0');
    signal btb_update_tgt : std_logic_vector(31 downto 0) := (others => '0');

    -- RAS signals
    signal ras_push_val   : std_logic := '0';
    signal ras_push_addr  : std_logic_vector(31 downto 0) := (others => '0');
    signal ras_pop_val    : std_logic := '0';
    signal ras_pop_addr   : std_logic_vector(31 downto 0);
    signal ras_pop_val_out: std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    u_gshare : entity work.talos_bpred_gshare
        generic map (
            GHR_BITS    => 10,
            PHT_ENTRIES => 1024
        )
        port map (
            clk              => clk,
            rst_n            => rst_n,
            fetch_pc         => gshare_fetch_pc,
            pred_taken       => gshare_pred_taken,
            spec_ghr_out     => gshare_spec_ghr,
            fetch_advance    => gshare_advance,
            fetch_pred_taken => gshare_pred_taken,
            resolve_valid    => gshare_resolve_val,
            resolve_pc       => gshare_resolve_pc,
            resolve_ghr      => gshare_resolve_ghr,
            resolve_taken    => gshare_resolve_tkn,
            resolve_mispred  => gshare_resolve_mis
        );

    u_btb : entity work.talos_btb
        generic map (
            SETS       => 128,
            INDEX_BITS => 7,
            TAG_BITS   => 23
        )
        port map (
            clk              => clk,
            rst_n            => rst_n,
            fetch_pc         => btb_fetch_pc,
            hit              => btb_hit,
            target_pc        => btb_target_pc,
            is_call          => open,
            is_return        => open,
            update_valid     => btb_update_val,
            update_pc        => btb_update_pc,
            update_target    => btb_update_tgt,
            update_is_call   => '0',
            update_is_return => '0'
        );

    u_ras : entity work.talos_ras
        generic map (
            DEPTH      => 16,
            INDEX_BITS => 4
        )
        port map (
            clk           => clk,
            rst_n         => rst_n,
            push_valid    => ras_push_val,
            push_addr     => ras_push_addr,
            pop_valid     => ras_pop_val,
            pop_addr      => ras_pop_addr,
            pop_valid_out => ras_pop_val_out,
            current_tos   => open,
            restore_valid => '0',
            restore_tos   => (others => '0')
        );

    process
    begin
        report "[TEST] Starting tb_talos_bpred verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        -- 1. Test BTB Update and Query
        btb_update_val <= '1';
        btb_update_pc  <= x"80000100";
        btb_update_tgt <= x"80000500";
        wait until rising_edge(clk);
        btb_update_val <= '0';
        wait until rising_edge(clk);

        -- Query BTB at 0x80000100
        btb_fetch_pc <= x"80000100";
        wait for 1 ns;
        assert btb_hit = '1' report "BTB should hit" severity failure;
        assert btb_target_pc = x"80000500" report "BTB target mismatch" severity failure;

        -- 2. Test RAS Push and Pop
        ras_push_val  <= '1';
        ras_push_addr <= x"80000104";
        wait until rising_edge(clk);
        ras_push_val  <= '0';
        wait until rising_edge(clk);

        -- Pop from RAS
        ras_pop_val <= '1';
        wait for 1 ns;
        assert ras_pop_val_out = '1' report "RAS pop should be valid" severity failure;
        assert ras_pop_addr = x"80000104" report "RAS pop address mismatch" severity failure;
        wait until rising_edge(clk);
        ras_pop_val <= '0';
        wait until rising_edge(clk);

        -- 3. Test Gshare Resolution
        gshare_resolve_val <= '1';
        gshare_resolve_pc  <= x"80000200";
        gshare_resolve_ghr <= (others => '0');
        gshare_resolve_tkn <= '1';
        gshare_resolve_mis <= '0';
        wait until rising_edge(clk);
        gshare_resolve_val <= '0';
        wait until rising_edge(clk);

        report "[PASS] tb_talos_bpred verification successful.";
        std.env.stop;
    end process;

end architecture sim;
