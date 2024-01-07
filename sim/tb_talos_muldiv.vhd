-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Radix-4 Multiplier and Non-Restoring Divider
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;

entity tb_talos_muldiv is
end entity tb_talos_muldiv;

architecture sim of tb_talos_muldiv is

    constant CLK_PERIOD : time := 10 ns;

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal flush : std_logic := '0';

    -- Multiplier signals
    signal mul_req_val     : std_logic := '0';
    signal mul_op          : muldiv_op_t := MD_MUL;
    signal mul_src1        : std_logic_vector(31 downto 0) := (others => '0');
    signal mul_src2        : std_logic_vector(31 downto 0) := (others => '0');
    signal mul_resp_val    : std_logic;
    signal mul_resp_res    : std_logic_vector(31 downto 0);

    -- Divider signals
    signal div_req_val     : std_logic := '0';
    signal div_op          : muldiv_op_t := MD_DIV;
    signal div_src1        : std_logic_vector(31 downto 0) := (others => '0');
    signal div_src2        : std_logic_vector(31 downto 0) := (others => '0');
    signal div_busy        : std_logic;
    signal div_resp_val    : std_logic;
    signal div_resp_res    : std_logic_vector(31 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    u_mult : entity work.talos_multiplier
        port map (
            clk         => clk,
            rst_n       => rst_n,
            flush       => flush,
            req_val     => mul_req_val,
            md_op       => mul_op,
            src1        => mul_src1,
            src2        => mul_src2,
            rob_idx_in  => (others => '0'),
            rd_phys_in  => (others => '0'),
            resp_val    => mul_resp_val,
            resp_res    => mul_resp_res,
            rob_idx_out => open,
            rd_phys_out => open
        );

    u_div : entity work.talos_divider
        port map (
            clk         => clk,
            rst_n       => rst_n,
            flush       => flush,
            req_val     => div_req_val,
            md_op       => div_op,
            src1        => div_src1,
            src2        => div_src2,
            rob_idx_in  => (others => '0'),
            rd_phys_in  => (others => '0'),
            busy        => div_busy,
            resp_val    => div_resp_val,
            resp_res    => div_resp_res,
            rob_idx_out => open,
            rd_phys_out => open
        );

    process
    begin
        report "[TEST] Starting tb_talos_muldiv verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        -- 1. Test Multiplier: 12 * 10 = 120
        mul_req_val <= '1';
        mul_op      <= MD_MUL;
        mul_src1    <= std_logic_vector(to_signed(12, 32));
        mul_src2    <= std_logic_vector(to_signed(10, 32));
        wait until rising_edge(clk);
        mul_req_val <= '0';

        -- Wait for 3-stage pipeline latency
        wait until mul_resp_val = '1';
        assert mul_resp_res = std_logic_vector(to_signed(120, 32))
            report "MUL 12*10 failed" severity failure;
        wait until rising_edge(clk);

        -- 2. Test Multiplier: -5 * 20 = -100
        mul_req_val <= '1';
        mul_op      <= MD_MUL;
        mul_src1    <= std_logic_vector(to_signed(-5, 32));
        mul_src2    <= std_logic_vector(to_signed(20, 32));
        wait until rising_edge(clk);
        mul_req_val <= '0';

        wait until mul_resp_val = '1';
        assert mul_resp_res = std_logic_vector(to_signed(-100, 32))
            report "MUL -5*20 failed" severity failure;
        wait until rising_edge(clk);

        -- 3. Test Divider: 100 / 10 = 10
        div_req_val <= '1';
        div_op      <= MD_DIV;
        div_src1    <= std_logic_vector(to_signed(100, 32));
        div_src2    <= std_logic_vector(to_signed(10, 32));
        wait until rising_edge(clk);
        div_req_val <= '0';

        wait until div_resp_val = '1';
        assert div_resp_res = std_logic_vector(to_signed(10, 32))
            report "DIV 100/10 failed" severity failure;
        wait until rising_edge(clk);

        -- 4. Test Remainder: 103 % 10 = 3
        div_req_val <= '1';
        div_op      <= MD_REM;
        div_src1    <= std_logic_vector(to_signed(103, 32));
        div_src2    <= std_logic_vector(to_signed(10, 32));
        wait until rising_edge(clk);
        div_req_val <= '0';

        wait until div_resp_val = '1';
        assert div_resp_res = std_logic_vector(to_signed(3, 32))
            report "REM 103%10 failed" severity failure;
        wait until rising_edge(clk);

        report "[PASS] tb_talos_muldiv verification successful.";
        std.env.stop;
    end process;

end architecture sim;
