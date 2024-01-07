-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Distributed Reservation Stations (Tag Matching and CDB Wakeup)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_rs is
end entity tb_talos_rs;

architecture sim of tb_talos_rs is

    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal flush      : std_logic := '0';

    signal push_val0  : std_logic := '0';
    signal push_pkt0  : rename_pkt_t := RENAME_PKT_ZERO;
    signal push_val1  : std_logic := '0';
    signal push_pkt1  : rename_pkt_t := RENAME_PKT_ZERO;
    signal rs_ready   : std_logic;

    signal cdb_bus    : cdb_bus_t := (others => CDB_ENTRY_ZERO);

    signal issue_val0 : std_logic;
    signal issue_pkt0 : rename_pkt_t;
    signal issue_val1 : std_logic;
    signal issue_pkt1 : rename_pkt_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_rs_alu
        port map (
            clk        => clk,
            rst_n      => rst_n,
            flush      => flush,
            push_val0  => push_val0,
            push_pkt0  => push_pkt0,
            push_val1  => push_val1,
            push_pkt1  => push_pkt1,
            rs_ready   => rs_ready,
            cdb_bus    => cdb_bus,
            issue_val0 => issue_val0,
            issue_pkt0 => issue_pkt0,
            issue_val1 => issue_val1,
            issue_pkt1 => issue_pkt1
        );

    process
    begin
        report "[TEST] Starting tb_talos_rs verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert rs_ready = '1' report "RS should be ready after reset" severity failure;

        -- 1. Push an instruction dependent on physical tag p45 (rs1_ready = '0')
        push_val0 <= '1';
        push_pkt0.valid     <= '1';
        push_pkt0.pc        <= x"80000020";
        push_pkt0.alu_op    <= ALU_ADD;
        push_pkt0.rs1_phys  <= "101101"; -- tag 45
        push_pkt0.rs1_ready <= '0';      -- pending producer!
        push_pkt0.rs2_phys  <= "000000"; -- zero
        push_pkt0.rs2_ready <= '1';
        push_pkt0.rd_phys   <= "110000"; -- tag 48
        push_pkt0.has_dest  <= '1';
        wait until rising_edge(clk);
        push_val0 <= '0';
        push_pkt0 <= RENAME_PKT_ZERO;

        -- Wait 1 cycle: instruction is queued in RS but NOT ready to issue
        wait until rising_edge(clk);
        assert issue_val0 = '0' and issue_val1 = '0'
            report "Instruction should not issue while operand is pending" severity failure;

        -- 2. Broadcast tag p45 on CDB (Producer completes execution)
        cdb_bus(0).valid    <= '1';
        cdb_bus(0).phys_tag <= "101101"; -- matches tag 45
        cdb_bus(0).value    <= x"0000002A"; -- result 42
        wait until rising_edge(clk);
        cdb_bus <= (others => CDB_ENTRY_ZERO);

        -- 3. Now operands are satisfied: instruction should wake up and issue!
        wait for 1 ns;
        assert issue_val0 = '1' report "Instruction failed to wake up and issue" severity failure;
        assert issue_pkt0.rd_phys = "110000" report "Issued packet rd tag mismatch" severity failure;

        wait until rising_edge(clk);
        wait for 1 ns;
        assert issue_val0 = '0' report "RS slot should be cleared after issue" severity failure;

        report "[PASS] tb_talos_rs verification successful.";
        std.env.stop;
    end process;

end architecture sim;
