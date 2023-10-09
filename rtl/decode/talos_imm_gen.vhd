-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Decode: Immediate Generator and Sign-Extension Unit
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_imm_gen is
    port (
        instr   : in  std_logic_vector(INSTR_WIDTH-1 downto 0);
        imm_i   : out std_logic_vector(XLEN-1 downto 0);
        imm_s   : out std_logic_vector(XLEN-1 downto 0);
        imm_b   : out std_logic_vector(XLEN-1 downto 0);
        imm_u   : out std_logic_vector(XLEN-1 downto 0);
        imm_j   : out std_logic_vector(XLEN-1 downto 0);
        imm_z   : out std_logic_vector(XLEN-1 downto 0) -- CSR immediate (zero-extended)
    );
end entity talos_imm_gen;

architecture rtl of talos_imm_gen is
begin

    -- I-type immediate (12-bit signed)
    process(instr)
        variable sign : std_logic;
    begin
        sign := instr(31);
        if sign = '1' then
            imm_i <= (31 downto 12 => '1') & instr(31 downto 20);
        else
            imm_i <= (31 downto 12 => '0') & instr(31 downto 20);
        end if;
    end process;

    -- S-type immediate (12-bit signed store offset)
    process(instr)
        variable sign : std_logic;
    begin
        sign := instr(31);
        if sign = '1' then
            imm_s <= (31 downto 12 => '1') & instr(31 downto 25) & instr(11 downto 7);
        else
            imm_s <= (31 downto 12 => '0') & instr(31 downto 25) & instr(11 downto 7);
        end if;
    end process;

    -- B-type immediate (13-bit signed branch displacement)
    process(instr)
        variable sign : std_logic;
    begin
        sign := instr(31);
        if sign = '1' then
            imm_b <= (31 downto 13 => '1') & instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';
        else
            imm_b <= (31 downto 13 => '0') & instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';
        end if;
    end process;

    -- U-type immediate (20-bit upper immediate)
    imm_u <= instr(31 downto 12) & x"000";

    -- J-type immediate (21-bit signed jump displacement)
    process(instr)
        variable sign : std_logic;
    begin
        sign := instr(31);
        if sign = '1' then
            imm_j <= (31 downto 21 => '1') & instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0';
        else
            imm_j <= (31 downto 21 => '0') & instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0';
        end if;
    end process;

    -- Z-type immediate (5-bit zero-extended CSR immediate from uimm field)
    imm_z <= (31 downto 5 => '0') & instr(19 downto 15);

end architecture rtl;
