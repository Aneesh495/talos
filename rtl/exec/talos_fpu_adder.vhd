-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: IEEE-754 Single-Precision Floating-Point Adder and Subtractor
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_fpu_pkg.all;

entity talos_fpu_adder is
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        req_val    : in  std_logic;
        is_sub     : in  std_logic;
        src1       : in  std_logic_vector(31 downto 0);
        src2       : in  std_logic_vector(31 downto 0);
        rm         : in  std_logic_vector(2 downto 0);
        res_val    : out std_logic;
        res_data   : out std_logic_vector(31 downto 0);
        res_flags  : out std_logic_vector(4 downto 0)
    );
end entity talos_fpu_adder;

architecture rtl of talos_fpu_adder is

    signal s_valid : std_logic := '0';
    signal s_res   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_flags : std_logic_vector(4 downto 0) := (others => '0');

begin

    process(clk, rst_n)
        variable sign1, sign2, eff_sub, res_sign : std_logic;
        variable exp1, exp2, max_exp             : signed(9 downto 0);
        variable exp_diff                        : integer;
        variable man1, man2                      : unsigned(26 downto 0);
        variable aligned_man1, aligned_man2      : unsigned(26 downto 0);
        variable sum_man                         : unsigned(27 downto 0);
        variable norm_man                        : unsigned(23 downto 0);
        variable final_exp                       : signed(9 downto 0);
        variable flags                           : std_logic_vector(4 downto 0);
    begin
        if rst_n = '0' then
            s_valid <= '0';
            s_res   <= (others => '0');
            s_flags <= (others => '0');
        elsif rising_edge(clk) then
            s_valid <= req_val;
            flags   := (others => '0');

            if req_val = '1' then
                sign1 := src1(FP32_SIGN_IDX);
                sign2 := src2(FP32_SIGN_IDX) xor is_sub;

                exp1 := signed("00" & src1(FP32_EXP_HIGH downto FP32_EXP_LOW));
                exp2 := signed("00" & src2(FP32_EXP_HIGH downto FP32_EXP_LOW));

                -- Special cases: NaN
                if fp_is_nan(src1) or fp_is_nan(src2) then
                    s_res   <= FP32_CANONICAL_QNAN;
                    flags(FP_FLAG_NV_BIT) := '1';

                -- Special cases: Zero
                elsif fp_is_zero(src1) and fp_is_zero(src2) then
                    s_res <= (sign1 and sign2) & (30 downto 0 => '0');

                elsif fp_is_zero(src1) then
                    s_res <= sign2 & src2(30 downto 0);

                elsif fp_is_zero(src2) then
                    s_res <= sign1 & src1(30 downto 0);

                else
                    -- Unpack mantissas with implicit leading 1
                    man1 := unsigned("01" & src1(22 downto 0) & "00");
                    man2 := unsigned("01" & src2(22 downto 0) & "00");

                    -- Align exponents
                    if exp1 >= exp2 then
                        max_exp  := exp1;
                        exp_diff := to_integer(exp1 - exp2);
                        aligned_man1 := man1;
                        if exp_diff > 26 then
                            aligned_man2 := (others => '0');
                        else
                            aligned_man2 := shift_right(man2, exp_diff);
                        end if;
                    else
                        max_exp  := exp2;
                        exp_diff := to_integer(exp2 - exp1);
                        aligned_man2 := man2;
                        if exp_diff > 26 then
                            aligned_man1 := (others => '0');
                        else
                            aligned_man1 := shift_right(man1, exp_diff);
                        end if;
                    end if;

                    eff_sub := sign1 xor sign2;

                    if eff_sub = '0' then
                        -- Addition of magnitudes
                        sum_man  := resize(aligned_man1, 28) + resize(aligned_man2, 28);
                        res_sign := sign1;

                        -- Check for overflow carry out
                        if sum_man(26) = '1' then
                            norm_man  := sum_man(26 downto 3);
                            final_exp := max_exp + 1;
                        else
                            norm_man  := sum_man(25 downto 2);
                            final_exp := max_exp;
                        end if;
                    else
                        -- Subtraction of magnitudes
                        if aligned_man1 >= aligned_man2 then
                            sum_man  := resize(aligned_man1 - aligned_man2, 28);
                            res_sign := sign1;
                        else
                            sum_man  := resize(aligned_man2 - aligned_man1, 28);
                            res_sign := sign2;
                        end if;

                        -- Leading zero normalization
                        if sum_man = 0 then
                            final_exp := (others => '0');
                            norm_man  := (others => '0');
                            res_sign  := '0';
                        elsif sum_man(25) = '1' then
                            norm_man  := sum_man(25 downto 2);
                            final_exp := max_exp;
                        elsif sum_man(24) = '1' then
                            norm_man  := sum_man(24 downto 1);
                            final_exp := max_exp - 1;
                        else
                            norm_man  := sum_man(23 downto 0);
                            final_exp := max_exp - 2;
                        end if;
                    end if;

                    s_res <= res_sign & std_logic_vector(final_exp(7 downto 0)) & std_logic_vector(norm_man(22 downto 0));
                end if;

                s_flags <= flags;
            end if;
        end if;
    end process;

    res_val   <= s_valid;
    res_data  <= s_res;
    res_flags <= s_flags;

end architecture rtl;
