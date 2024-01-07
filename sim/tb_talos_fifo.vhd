-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Generic Synchronous FIFO with Watermarks and Flush
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_talos_fifo is
end entity tb_talos_fifo;

architecture sim of tb_talos_fifo is

    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal flush        : std_logic := '0';
    signal wr_en        : std_logic := '0';
    signal wr_data      : std_logic_vector(31 downto 0) := (others => '0');
    signal full         : std_logic;
    signal almost_full  : std_logic;
    signal rd_en        : std_logic := '0';
    signal rd_data      : std_logic_vector(31 downto 0);
    signal empty        : std_logic;
    signal almost_empty : std_logic;
    signal count        : std_logic_vector(7 downto 0);

begin

    -- Clock Generator
    clk <= not clk after CLK_PERIOD / 2;

    -- Device Under Test
    dut : entity work.talos_fifo
        generic map (
            DATA_WIDTH          => 32,
            DEPTH               => 8,
            ALMOST_FULL_THRESH  => 7,
            ALMOST_EMPTY_THRESH => 1
        )
        port map (
            clk          => clk,
            rst_n        => rst_n,
            flush        => flush,
            wr_en        => wr_en,
            wr_data      => wr_data,
            full         => full,
            almost_full  => almost_full,
            rd_en        => rd_en,
            rd_data      => rd_data,
            empty        => empty,
            almost_empty => almost_empty,
            count        => count
        );

    process
    begin
        report "[TEST] Starting tb_talos_fifo verification...";

        -- Reset Sequence
        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert empty = '1' report "FIFO should be empty on reset" severity failure;
        assert full = '0' report "FIFO should not be full on reset" severity failure;

        -- Write 4 entries: 0x10, 0x20, 0x30, 0x40
        for i in 1 to 4 loop
            wr_en   <= '1';
            wr_data <= std_logic_vector(to_unsigned(i * 16, 32));
            wait until rising_edge(clk);
        end loop;
        wr_en <= '0';
        wait until rising_edge(clk);

        assert empty = '0' report "FIFO should not be empty after writes" severity failure;
        assert unsigned(count) = 4 report "Count should be 4" severity failure;

        -- Read 4 entries and verify values
        for i in 1 to 4 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            assert rd_data = std_logic_vector(to_unsigned(i * 16, 32))
                report "FIFO read data mismatch" severity failure;
        end loop;
        rd_en <= '0';
        wait until rising_edge(clk);

        assert empty = '1' report "FIFO should be empty after reading all entries" severity failure;

        -- Test Flush
        for i in 1 to 3 loop
            wr_en   <= '1';
            wr_data <= std_logic_vector(to_unsigned(i * 100, 32));
            wait until rising_edge(clk);
        end loop;
        wr_en <= '0';
        wait until rising_edge(clk);

        flush <= '1';
        wait until rising_edge(clk);
        flush <= '0';
        wait until rising_edge(clk);

        assert empty = '1' report "FIFO should be empty after flush" severity failure;

        report "[PASS] tb_talos_fifo verification successful.";
        std.env.stop;
    end process;

end architecture sim;
