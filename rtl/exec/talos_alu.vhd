-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: Single-Cycle 32-Bit Arithmetic Logic Unit (ALU)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_alu is
    port (
        alu_op : in  alu_op_t;
        src1   : in  std_logic_vector(XLEN-1 downto 0);
        src2   : in  std_logic_vector(XLEN-1 downto 0);
        pc     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        imm    : in  std_logic_vector(XLEN-1 downto 0);
        res    : out std_logic_vector(XLEN-1 downto 0);
        zero   : out std_logic
    );
end entity talos_alu;

architecture rtl of talos_alu is
begin

    process(alu_op, src1, src2, pc, imm)
        variable s1_signed   : signed(XLEN-1 downto 0);
        variable s2_signed   : signed(XLEN-1 downto 0);
        variable s1_unsigned : unsigned(XLEN-1 downto 0);
        variable s2_unsigned : unsigned(XLEN-1 downto 0);
        variable shamt       : integer range 0 to 31;
        variable r           : std_logic_vector(XLEN-1 downto 0);
    begin
        s1_signed   := signed(src1);
        s2_signed   := signed(src2);
        s1_unsigned := unsigned(src1);
        s2_unsigned := unsigned(src2);
        shamt       := to_integer(unsigned(src2(4 downto 0)));
        r           := (others => '0');

        case alu_op is
            when ALU_ADD =>
                r := std_logic_vector(s1_unsigned + s2_unsigned);

            when ALU_SUB =>
                r := std_logic_vector(s1_unsigned - s2_unsigned);

            when ALU_SLL =>
                r := std_logic_vector(shift_left(s1_unsigned, shamt));

            when ALU_SLT =>
                if s1_signed < s2_signed then
                    r := (0 => '1', others => '0');
                else
                    r := (others => '0');
                end if;

            when ALU_SLTU =>
                if s1_unsigned < s2_unsigned then
                    r := (0 => '1', others => '0');
                else
                    r := (others => '0');
                end if;

            when ALU_XOR =>
                r := src1 xor src2;

            when ALU_SRL =>
                r := std_logic_vector(shift_right(s1_unsigned, shamt));

            when ALU_SRA =>
                r := std_logic_vector(shift_right(s1_signed, shamt));

            when ALU_OR =>
                r := src1 or src2;

            when ALU_AND =>
                r := src1 and src2;

            when ALU_LUI =>
                r := imm;

            when ALU_AUIPC =>
                r := std_logic_vector(unsigned(pc) + unsigned(imm));

            when others =>
                r := (others => '0');
        end case;

        res <= r;
        if r = (r'range => '0') then
            zero <= '1';
        else
            zero <= '0';
        end if;
    end process;

end architecture rtl;
