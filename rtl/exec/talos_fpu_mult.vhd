-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: IEEE-754 Single-Precision Floating-Point Multiplier
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_fpu_pkg.all;

entity talos_fpu_mult is
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        req_val    : in  std_logic;
        src1       : in  std_logic_vector(31 downto 0);
        src2       : in  std_logic_vector(31 downto 0);
        rm         : in  std_logic_vector(2 downto 0);
        res_val    : out std_logic;
        res_data   : out std_logic_vector(31 downto 0);
        res_flags  : out std_logic_vector(4 downto 0)
    );
end entity talos_fpu_mult;

architecture rtl of talos_fpu_mult is

    signal s_valid : std_logic := '0';
    signal s_res   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_flags : std_logic_vector(4 downto 0) := (others => '0');

begin

    process(clk, rst_n)
        variable sign1, sign2, res_sign : std_logic;
        variable exp1, exp2, sum_exp    : signed(9 downto 0);
        variable man1, man2             : unsigned(23 downto 0);
        variable prod_man               : unsigned(47 downto 0);
        variable norm_man               : unsigned(22 downto 0);
        variable final_exp              : signed(9 downto 0);
        variable flags                  : std_logic_vector(4 downto 0);
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
                sign2 := src2(FP32_SIGN_IDX);
                res_sign := sign1 xor sign2;

                exp1 := signed("00" & src1(FP32_EXP_HIGH downto FP32_EXP_LOW));
                exp2 := signed("00" & src2(FP32_EXP_HIGH downto FP32_EXP_LOW));

                -- Special cases: NaN
                if fp_is_nan(src1) or fp_is_nan(src2) then
                    s_res <= FP32_CANONICAL_QNAN;
                    flags(FP_FLAG_NV_BIT) := '1';

                -- Special cases: 0 * Inf = NaN
                elsif (fp_is_zero(src1) and fp_is_inf(src2)) or (fp_is_inf(src1) and fp_is_zero(src2)) then
                    s_res <= FP32_CANONICAL_QNAN;
                    flags(FP_FLAG_NV_BIT) := '1';

                -- Special cases: Infinity
                elsif fp_is_inf(src1) or fp_is_inf(src2) then
                    s_res <= res_sign & x"FF" & (22 downto 0 => '0');

                -- Special cases: Zero
                elsif fp_is_zero(src1) or fp_is_zero(src2) then
                    s_res <= res_sign & (30 downto 0 => '0');

                else
                    man1 := unsigned("1" & src1(22 downto 0));
                    man2 := unsigned("1" & src2(22 downto 0));

                    prod_man := man1 * man2;
                    sum_exp  := exp1 + exp2 - to_signed(FP32_EXP_BIAS, 10);

                    if prod_man(47) = '1' then
                        norm_man  := prod_man(46 downto 24);
                        final_exp := sum_exp + 1;
                    else
                        norm_man  := prod_man(45 downto 23);
                        final_exp := sum_exp;
                    end if;

                    -- Underflow / Overflow check
                    if final_exp >= 255 then
                        s_res <= res_sign & x"FF" & (22 downto 0 => '0'); -- Inf
                        flags(FP_FLAG_OF_BIT) := '1';
                        flags(FP_FLAG_NX_BIT) := '1';
                    elsif final_exp <= 0 then
                        s_res <= res_sign & (30 downto 0 => '0'); -- Flush to zero
                        flags(FP_FLAG_UF_BIT) := '1';
                        flags(FP_FLAG_NX_BIT) := '1';
                    else
                        s_res <= res_sign & std_logic_vector(final_exp(7 downto 0)) & std_logic_vector(norm_man);
                    end if;
                end if;

                s_flags <= flags;
            end if;
        end if;
    end process;

    res_val   <= s_valid;
    res_data  <= s_res;
    res_flags <= s_flags;

end architecture rtl;
