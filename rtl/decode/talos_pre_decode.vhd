-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Decode: Fast Pre-Decoder and Instruction Boundary Classifier
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_rv32_pkg.all;

entity talos_pre_decode is
    port (
        instr      : in  std_logic_vector(INSTR_WIDTH-1 downto 0);
        is_branch  : out std_logic;
        is_jal     : out std_logic;
        is_jalr    : out std_logic;
        is_call    : out std_logic;
        is_return  : out std_logic;
        is_load    : out std_logic;
        is_store   : out std_logic;
        is_system  : out std_logic;
        is_fence   : out std_logic
    );
end entity talos_pre_decode;

architecture rtl of talos_pre_decode is

    signal opcode : std_logic_vector(6 downto 0);
    signal rd     : std_logic_vector(4 downto 0);
    signal rs1    : std_logic_vector(4 downto 0);

begin

    opcode <= instr(6 downto 0);
    rd     <= instr(11 downto 7);
    rs1    <= instr(19 downto 15);

    is_branch <= '1' when opcode = OPC_BRANCH else '0';
    is_jal    <= '1' when opcode = OPC_JAL    else '0';
    is_jalr   <= '1' when opcode = OPC_JALR   else '0';
    is_load   <= '1' when (opcode = OPC_LOAD or opcode = OPC_LOAD_FP) else '0';
    is_store  <= '1' when (opcode = OPC_STORE or opcode = OPC_STORE_FP) else '0';
    is_system <= '1' when opcode = OPC_SYSTEM else '0';
    is_fence  <= '1' when opcode = OPC_MISC_MEM else '0';

    -- Call detection: JAL or JALR where rd is link register x1 (ra) or x5 (t0)
    process(opcode, rd)
    begin
        if (opcode = OPC_JAL or opcode = OPC_JALR) and (rd = "00001" or rd = "00101") then
            is_call <= '1';
        else
            is_call <= '0';
        end if;
    end process;

    -- Return detection: JALR where rd is x0 and rs1 is link register x1 or x5
    process(opcode, rd, rs1)
    begin
        if (opcode = OPC_JALR) and (rd = "00000") and (rs1 = "00001" or rs1 = "00101") then
            is_return <= '1';
        else
            is_return <= '0';
        end if;
    end process;

end architecture rtl;
