-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: IEEE-754 Floating-Point Unit Top Pipeline
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;
use work.talos_fpu_pkg.all;

entity tb_talos_fpu is
end entity tb_talos_fpu;

architecture sim of tb_talos_fpu is

    constant CLK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal flush       : std_logic := '0';

    signal req_val     : std_logic := '0';
    signal fpu_op      : fpu_op_t := FPU_ADD;
    signal src1        : std_logic_vector(31 downto 0) := (others => '0');
    signal src2        : std_logic_vector(31 downto 0) := (others => '0');
    signal src3        : std_logic_vector(31 downto 0) := (others => '0');
    signal rm          : std_logic_vector(2 downto 0) := "000";
    signal resp_val    : std_logic;
    signal resp_data   : std_logic_vector(31 downto 0);
    signal resp_flags  : std_logic_vector(4 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_fpu_top
        port map (
            clk         => clk,
            rst_n       => rst_n,
            flush       => flush,
            req_val     => req_val,
            fpu_op      => fpu_op,
            src1        => src1,
            src2        => src2,
            src3        => src3,
            rm          => rm,
            rob_idx_in  => (others => '0'),
            rd_phys_in  => (others => '0'),
            resp_val    => resp_val,
            resp_data   => resp_data,
            resp_flags  => resp_flags,
            rob_idx_out => open,
            rd_phys_out => open
        );

    process
    begin
        report "[TEST] Starting tb_talos_fpu verification...";

        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        -- 1. FADD: 1.5f + 2.5f = 4.0f (0x3FC00000 + 0x40200000 = 0x40800000)
        req_val <= '1';
        fpu_op  <= FPU_ADD;
        src1    <= x"3FC00000";
        src2    <= x"40200000";
        wait until rising_edge(clk);
        req_val <= '0';

        wait until resp_val = '1';
        assert resp_data = x"40800000" report "FADD failed" severity failure;
        wait until rising_edge(clk);

        -- 2. FSUB: 4.0f - 1.5f = 2.5f (0x40800000 - 0x3FC00000 = 0x40200000)
        req_val <= '1';
        fpu_op  <= FPU_SUB;
        src1    <= x"40800000";
        src2    <= x"3FC00000";
        wait until rising_edge(clk);
        req_val <= '0';

        wait until resp_val = '1';
        assert resp_data = x"40200000" report "FSUB failed" severity failure;
        wait until rising_edge(clk);

        -- 3. FMUL: 2.0f * 3.0f = 6.0f (0x40000000 * 0x40400000 = 0x40C00000)
        req_val <= '1';
        fpu_op  <= FPU_MUL;
        src1    <= x"40000000";
        src2    <= x"40400000";
        wait until rising_edge(clk);
        req_val <= '0';

        wait until resp_val = '1';
        assert resp_data = x"40C00000" report "FMUL failed" severity failure;
        wait until rising_edge(clk);

        -- 4. FCVT_S_W: integer 10 -> float 10.0f (0x41200000)
        req_val <= '1';
        fpu_op  <= FPU_CVT_S_W;
        src1    <= std_logic_vector(to_signed(10, 32));
        wait until rising_edge(clk);
        req_val <= '0';

        wait until resp_val = '1';
        assert resp_data = x"41200000" report "FCVT_S_W failed" severity failure;
        wait until rising_edge(clk);

        report "[PASS] tb_talos_fpu verification successful.";
        std.env.stop;
    end process;

end architecture sim;
