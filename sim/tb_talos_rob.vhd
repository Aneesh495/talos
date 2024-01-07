-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: 32-Entry Circular Reorder Buffer (In-Order Retirement)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_rob is
end entity tb_talos_rob;

architecture sim of tb_talos_rob is

    constant CLK_PERIOD : time := 10 ns;

    signal clk            : std_logic := '0';
    signal rst_n          : std_logic := '0';
    signal flush          : std_logic := '0';

    -- Allocation interface
    signal alloc_val0     : std_logic := '0';
    signal alloc_pc0      : std_logic_vector(31 downto 0) := x"80000000";
    signal alloc_rd_arch0 : std_logic_vector(4 downto 0)  := "01010"; -- a0
    signal alloc_rd_phys0 : std_logic_vector(5 downto 0)  := "100000"; -- p32
    signal alloc_old_phys0: std_logic_vector(5 downto 0)  := "001010"; -- p10

    signal alloc_val1     : std_logic := '0';
    signal alloc_pc1      : std_logic_vector(31 downto 0) := x"80000004";
    signal alloc_rd_arch1 : std_logic_vector(4 downto 0)  := "01011"; -- a1
    signal alloc_rd_phys1 : std_logic_vector(5 downto 0)  := "100001"; -- p33
    signal alloc_old_phys1: std_logic_vector(5 downto 0)  := "001011"; -- p11

    signal rob_has_space1 : std_logic;
    signal rob_has_space2 : std_logic;
    signal alloc_idx0     : std_logic_vector(4 downto 0);
    signal alloc_idx1     : std_logic_vector(4 downto 0);

    -- CDB interface
    signal cdb_bus        : cdb_bus_t := (others => CDB_ENTRY_ZERO);

    -- Commit interface
    signal commit_val0    : std_logic;
    signal commit_val1    : std_logic;
    signal commit_rd_phys0: std_logic_vector(5 downto 0);
    signal commit_rd_phys1: std_logic_vector(5 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_rob
        port map (
            clk               => clk,
            rst_n             => rst_n,
            flush             => flush,
            alloc_val0        => alloc_val0,
            alloc_pc0         => alloc_pc0,
            alloc_rd_arch0    => alloc_rd_arch0,
            alloc_rd_phys0    => alloc_rd_phys0,
            alloc_old_phys0   => alloc_old_phys0,
            alloc_has_dest0   => '1',
            alloc_is_store0   => '0',
            alloc_is_branch0  => '0',
            alloc_ckpt_id0    => (others => '0'),
            alloc_val1        => alloc_val1,
            alloc_pc1         => alloc_pc1,
            alloc_rd_arch1    => alloc_rd_arch1,
            alloc_rd_phys1    => alloc_rd_phys1,
            alloc_old_phys1   => alloc_old_phys1,
            alloc_has_dest1   => '1',
            alloc_is_store1   => '0',
            alloc_is_branch1  => '0',
            alloc_ckpt_id1    => (others => '0'),
            rob_has_space1    => rob_has_space1,
            rob_has_space2    => rob_has_space2,
            alloc_idx0_out    => alloc_idx0,
            alloc_idx1_out    => alloc_idx1,
            cdb_bus           => cdb_bus,
            branch_resolved   => '0',
            branch_rob_idx    => (others => '0'),
            branch_mispred    => '0',
            branch_target_pc  => (others => '0'),
            commit_val0       => commit_val0,
            commit_rd_arch0   => open,
            commit_rd_phys0   => commit_rd_phys0,
            commit_old_phys0  => open,
            commit_is_store0  => open,
            commit_is_branch0 => open,
            commit_ckpt_id0   => open,
            commit_val1       => commit_val1,
            commit_rd_arch1   => open,
            commit_rd_phys1   => commit_rd_phys1,
            commit_old_phys1  => open,
            commit_is_store1  => open,
            commit_is_branch1 => open,
            commit_ckpt_id1   => open,
            trap_val          => open,
            trap_pc           => open,
            trap_cause        => open,
            trap_epc          => open,
            mispred_val       => open,
            mispred_pc        => open,
            mispred_ckpt_id   => open
        );

    process
        variable target_idx0 : std_logic_vector(4 downto 0);
        variable target_idx1 : std_logic_vector(4 downto 0);
    begin
        report "[TEST] Starting tb_talos_rob verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert rob_has_space1 = '1' and rob_has_space2 = '1'
            report "ROB should have space on reset" severity failure;

        -- 1. Sample allocated indices and allocate two instructions
        target_idx0 := alloc_idx0;
        target_idx1 := alloc_idx1;
        alloc_val0  <= '1';
        alloc_val1  <= '1';
        wait until rising_edge(clk);
        alloc_val0  <= '0';
        alloc_val1  <= '0';

        -- 2. Out-of-order completion: Complete instruction 1 on CDB first!
        cdb_bus(0).valid    <= '1';
        cdb_bus(0).rob_idx  <= target_idx1;
        cdb_bus(0).phys_tag <= "100001";
        cdb_bus(0).value    <= x"00000005";
        wait until rising_edge(clk);
        cdb_bus <= (others => CDB_ENTRY_ZERO);

        -- Verify that inst 1 does NOT commit yet (inst 0 at head is still executing!)
        wait for 1 ns;
        assert commit_val0 = '0' and commit_val1 = '0'
            report "ROB committed out of order! Strict in-order commit violated." severity failure;

        -- 3. Now complete instruction 0 on CDB
        cdb_bus(0).valid    <= '1';
        cdb_bus(0).rob_idx  <= target_idx0;
        cdb_bus(0).phys_tag <= "100000";
        cdb_bus(0).value    <= x"0000000A";
        wait until rising_edge(clk);
        cdb_bus <= (others => CDB_ENTRY_ZERO);

        -- Both instructions are now ready and should retire in program order
        wait for 1 ns;
        assert commit_val0 = '1' report "Inst 0 should commit" severity failure;
        assert commit_rd_phys0 = "100000" report "Inst 0 commit phys reg mismatch" severity failure;
        assert commit_val1 = '1' report "Inst 1 should commit" severity failure;
        assert commit_rd_phys1 = "100001" report "Inst 1 commit phys reg mismatch" severity failure;

        wait until rising_edge(clk);
        wait for 1 ns;
        assert commit_val0 = '0' and commit_val1 = '0'
            report "ROB should be empty after commits" severity failure;

        report "[PASS] tb_talos_rob verification successful.";
        std.env.stop;
    end process;

end architecture sim;
