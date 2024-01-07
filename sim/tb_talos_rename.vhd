-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Register Renaming, Speculative RAT, and Checkpointing
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_rename is
end entity tb_talos_rename;

architecture sim of tb_talos_rename is

    constant CLK_PERIOD : time := 10 ns;

    signal clk           : std_logic := '0';
    signal rst_n         : std_logic := '0';
    signal flush         : std_logic := '0';
    signal stall         : std_logic := '0';

    signal decode_bundle : decode_bundle_t := (others => DECODE_PKT_ZERO);
    signal rename_ready  : std_logic;
    signal cdb_bus       : cdb_bus_t := (others => CDB_ENTRY_ZERO);
    signal rename_bundle : rename_bundle_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_rename_top
        port map (
            clk               => clk,
            rst_n             => rst_n,
            flush             => flush,
            stall             => stall,
            decode_bundle     => decode_bundle,
            rename_ready      => rename_ready,
            current_ghr       => (others => '0'),
            current_tos       => (others => '0'),
            cdb_bus           => cdb_bus,
            rollback_valid    => '0',
            rollback_id       => (others => '0'),
            commit_val0       => '0',
            commit_rd_arch0   => (others => '0'),
            commit_rd_phys0   => (others => '0'),
            commit_old_phys0  => (others => '0'),
            commit_val1       => '0',
            commit_rd_arch1   => (others => '0'),
            commit_rd_phys1   => (others => '0'),
            commit_old_phys1  => (others => '0'),
            commit_is_branch0 => '0',
            commit_ckpt_id0   => (others => '0'),
            commit_is_branch1 => '0',
            commit_ckpt_id1   => (others => '0'),
            rename_bundle     => rename_bundle
        );

    process
    begin
        report "[TEST] Starting tb_talos_rename verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert rename_ready = '1' report "Rename stage should be ready" severity failure;

        -- Instruction 0: addi a0, zero, 10 (rd_arch=10, rs1_arch=0)
        decode_bundle(0).valid     <= '1';
        decode_bundle(0).pc        <= x"80000000";
        decode_bundle(0).rd_arch   <= "01010"; -- 10 (a0)
        decode_bundle(0).has_dest  <= '1';
        decode_bundle(0).rs1_arch  <= "00000"; -- 0 (zero)
        decode_bundle(0).rs2_arch  <= "00000";

        -- Instruction 1: addi a1, a0, 5 (rd_arch=11, rs1_arch=10 -> intra-cycle RAW dependence on inst 0!)
        decode_bundle(1).valid     <= '1';
        decode_bundle(1).pc        <= x"80000004";
        decode_bundle(1).rd_arch   <= "01011"; -- 11 (a1)
        decode_bundle(1).has_dest  <= '1';
        decode_bundle(1).rs1_arch  <= "01010"; -- 10 (a0)
        decode_bundle(1).rs2_arch  <= "00000";

        wait until rising_edge(clk);
        wait for 1 ns;

        -- Verify physical registers were allocated
        assert rename_bundle(0).valid = '1' report "Inst 0 rename invalid" severity failure;
        assert rename_bundle(1).valid = '1' report "Inst 1 rename invalid" severity failure;
        assert unsigned(rename_bundle(0).rd_phys) >= 32 report "Inst 0 rd_phys should be speculative" severity failure;
        assert unsigned(rename_bundle(1).rd_phys) >= 32 report "Inst 1 rd_phys should be speculative" severity failure;
        assert rename_bundle(0).rd_phys /= rename_bundle(1).rd_phys report "Allocated tags should be distinct" severity failure;

        -- Verify intra-cycle forwarding: rs1_phys of inst 1 must match rd_phys of inst 0!
        assert rename_bundle(1).rs1_phys = rename_bundle(0).rd_phys
            report "Intra-cycle rename forwarding failed" severity failure;

        wait until rising_edge(clk);
        decode_bundle <= (others => DECODE_PKT_ZERO);
        wait until rising_edge(clk);

        report "[PASS] tb_talos_rename verification successful.";
        std.env.stop;
    end process;

end architecture sim;
