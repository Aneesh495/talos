-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Floating-Point Package: IEEE-754 Binary32 Formats, Rounding, and Flags
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package talos_fpu_pkg is

    -- -------------------------------------------------------------------------
    -- Binary32 Layout Constants
    -- -------------------------------------------------------------------------
    constant FP32_WIDTH             : integer := 32;
    constant FP32_EXP_WIDTH         : integer := 8;
    constant FP32_MAN_WIDTH         : integer := 23;
    constant FP32_EXP_BIAS          : integer := 127;

    -- Canonical Bitfield Offsets
    constant FP32_SIGN_IDX          : integer := 31;
    constant FP32_EXP_HIGH          : integer := 30;
    constant FP32_EXP_LOW           : integer := 23;
    constant FP32_MAN_HIGH          : integer := 22;
    constant FP32_MAN_LOW           : integer := 0;

    -- Canonical Special Constants
    constant FP32_POS_ZERO          : std_logic_vector(31 downto 0) := x"00000000";
    constant FP32_NEG_ZERO          : std_logic_vector(31 downto 0) := x"80000000";
    constant FP32_POS_INF           : std_logic_vector(31 downto 0) := x"7F800000";
    constant FP32_NEG_INF           : std_logic_vector(31 downto 0) := x"FF800000";
    constant FP32_CANONICAL_QNAN    : std_logic_vector(31 downto 0) := x"7FC00000";

    -- -------------------------------------------------------------------------
    -- Rounding Modes (RISC-V RM field)
    -- -------------------------------------------------------------------------
    constant RM_RNE                 : std_logic_vector(2 downto 0) := "000"; -- Round to Nearest, ties to Even
    constant RM_RTZ                 : std_logic_vector(2 downto 0) := "001"; -- Round towards Zero
    constant RM_RDN                 : std_logic_vector(2 downto 0) := "010"; -- Round Down towards -Infinity
    constant RM_RUP                 : std_logic_vector(2 downto 0) := "011"; -- Round Up towards +Infinity
    constant RM_RMM                 : std_logic_vector(2 downto 0) := "100"; -- Round to Nearest, ties to Max Magnitude
    constant RM_DYN                 : std_logic_vector(2 downto 0) := "111"; -- Dynamic mode in fcsr.frm

    -- -------------------------------------------------------------------------
    -- Exception Flags (RISC-V fflags bit positions)
    -- -------------------------------------------------------------------------
    constant FP_FLAG_NX_BIT         : integer := 0; -- Inexact
    constant FP_FLAG_UF_BIT         : integer := 1; -- Underflow
    constant FP_FLAG_OF_BIT         : integer := 2; -- Overflow
    constant FP_FLAG_DZ_BIT         : integer := 3; -- Divide by Zero
    constant FP_FLAG_NV_BIT         : integer := 4; -- Invalid Operation

    -- -------------------------------------------------------------------------
    -- Unpacked Floating-Point Internal Representation
    -- -------------------------------------------------------------------------
    type fp_unpacked_t is record
        sign        : std_logic;
        exp         : signed(FP32_EXP_WIDTH+1 downto 0); -- Unbiased exponent with overflow guard
        man         : unsigned(FP32_MAN_WIDTH+4 downto 0); -- Extended mantissa with guard/round/sticky
        is_zero     : std_logic;
        is_subnormal: std_logic;
        is_inf      : std_logic;
        is_nan      : std_logic;
        is_snan     : std_logic;
    end record fp_unpacked_t;

    -- -------------------------------------------------------------------------
    -- Helper Classification Functions
    -- -------------------------------------------------------------------------
    function fp_is_nan(val : std_logic_vector(31 downto 0)) return boolean;
    function fp_is_snan(val : std_logic_vector(31 downto 0)) return boolean;
    function fp_is_inf(val : std_logic_vector(31 downto 0)) return boolean;
    function fp_is_zero(val : std_logic_vector(31 downto 0)) return boolean;

end package talos_fpu_pkg;

package body talos_fpu_pkg is

    function fp_is_nan(val : std_logic_vector(31 downto 0)) return boolean is
        variable exp : std_logic_vector(7 downto 0);
        variable man : std_logic_vector(22 downto 0);
    begin
        exp := val(FP32_EXP_HIGH downto FP32_EXP_LOW);
        man := val(FP32_MAN_HIGH downto FP32_MAN_LOW);
        return (exp = x"FF") and (man /= (man'range => '0'));
    end function fp_is_nan;

    function fp_is_snan(val : std_logic_vector(31 downto 0)) return boolean is
        variable exp : std_logic_vector(7 downto 0);
        variable man : std_logic_vector(22 downto 0);
    begin
        exp := val(FP32_EXP_HIGH downto FP32_EXP_LOW);
        man := val(FP32_MAN_HIGH downto FP32_MAN_LOW);
        return (exp = x"FF") and (man(22) = '0') and (man /= (man'range => '0'));
    end function fp_is_snan;

    function fp_is_inf(val : std_logic_vector(31 downto 0)) return boolean is
        variable exp : std_logic_vector(7 downto 0);
        variable man : std_logic_vector(22 downto 0);
    begin
        exp := val(FP32_EXP_HIGH downto FP32_EXP_LOW);
        man := val(FP32_MAN_HIGH downto FP32_MAN_LOW);
        return (exp = x"FF") and (man = (man'range => '0'));
    end function fp_is_inf;

    function fp_is_zero(val : std_logic_vector(31 downto 0)) return boolean is
        variable exp_man : std_logic_vector(30 downto 0);
    begin
        exp_man := val(30 downto 0);
        return exp_man = (exp_man'range => '0');
    end function fp_is_zero;

end package body talos_fpu_pkg;
