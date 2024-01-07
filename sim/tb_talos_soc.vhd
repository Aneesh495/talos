-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Integration Testbench: Complete Top-Level SoC System Verification
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_soc is
end entity tb_talos_soc;

architecture sim of tb_talos_soc is

    constant CLK_PERIOD : time := 10 ns;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal uart_rx  : std_logic := '1'; -- Idle high
    signal uart_tx  : std_logic;
    signal ext_irq  : std_logic := '0';
    signal gpio_out : std_logic_vector(7 downto 0);
    signal gpio_in  : std_logic_vector(7 downto 0) := x"A5";

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_soc
        generic map (
            CLOCK_FREQ      => 50000000,
            BAUD_RATE       => 115200,
            BRAM_ADDR_WIDTH => 14 -- 16KB on-chip RAM
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            uart_rx  => uart_rx,
            uart_tx  => uart_tx,
            ext_irq  => ext_irq,
            gpio_out => gpio_out,
            gpio_in  => gpio_in
        );

    process
    begin
        report "[TEST] Starting tb_talos_soc top-level integration verification...";

        rst_n <= '0';
        wait for 30 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        -- Run simulation for 100 cycles to allow Boot ROM jump and BRAM fetch execution
        for i in 1 to 100 loop
            wait until rising_edge(clk);
        end loop;

        -- Verify UART transmitter is in idle marking state (high)
        assert uart_tx = '1' report "UART TX line should be high in idle state" severity failure;

        -- Verify GPIO reflects system inputs
        assert gpio_out(7 downto 6) = gpio_in(1 downto 0)
            report "GPIO diagnostic routing mismatch" severity failure;

        report "[PASS] tb_talos_soc top-level integration verification successful.";
        std.env.stop;
    end process;

end architecture sim;
