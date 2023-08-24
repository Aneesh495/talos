-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- ISA Package: RV32IMF Opcodes, Funct3/Funct7, CSR Addresses, and Trap Causes
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package talos_rv32_pkg is

    -- -------------------------------------------------------------------------
    -- RISC-V 7-bit Major Opcode Constants
    -- -------------------------------------------------------------------------
    constant OPC_LOAD               : std_logic_vector(6 downto 0) := "0000011";
    constant OPC_LOAD_FP            : std_logic_vector(6 downto 0) := "0000111";
    constant OPC_MISC_MEM           : std_logic_vector(6 downto 0) := "0001111";
    constant OPC_OP_IMM             : std_logic_vector(6 downto 0) := "0010011";
    constant OPC_AUIPC              : std_logic_vector(6 downto 0) := "0010111";
    constant OPC_STORE              : std_logic_vector(6 downto 0) := "0100011";
    constant OPC_STORE_FP           : std_logic_vector(6 downto 0) := "0100111";
    constant OPC_AMO                : std_logic_vector(6 downto 0) := "0101111";
    constant OPC_OP                 : std_logic_vector(6 downto 0) := "0110011";
    constant OPC_LUI                : std_logic_vector(6 downto 0) := "0110111";
    constant OPC_OP_FP              : std_logic_vector(6 downto 0) := "1010011";
    constant OPC_BRANCH             : std_logic_vector(6 downto 0) := "1100011";
    constant OPC_JALR               : std_logic_vector(6 downto 0) := "1100111";
    constant OPC_JAL                : std_logic_vector(6 downto 0) := "1101111";
    constant OPC_SYSTEM             : std_logic_vector(6 downto 0) := "1110011";

    -- -------------------------------------------------------------------------
    -- Funct3 Constants for Branches (OPC_BRANCH)
    -- -------------------------------------------------------------------------
    constant FUNCT3_BEQ             : std_logic_vector(2 downto 0) := "000";
    constant FUNCT3_BNE             : std_logic_vector(2 downto 0) := "001";
    constant FUNCT3_BLT             : std_logic_vector(2 downto 0) := "100";
    constant FUNCT3_BGE             : std_logic_vector(2 downto 0) := "101";
    constant FUNCT3_BLTU            : std_logic_vector(2 downto 0) := "110";
    constant FUNCT3_BGEU            : std_logic_vector(2 downto 0) := "111";

    -- -------------------------------------------------------------------------
    -- Funct3 Constants for Loads (OPC_LOAD)
    -- -------------------------------------------------------------------------
    constant FUNCT3_LB              : std_logic_vector(2 downto 0) := "000";
    constant FUNCT3_LH              : std_logic_vector(2 downto 0) := "001";
    constant FUNCT3_LW              : std_logic_vector(2 downto 0) := "010";
    constant FUNCT3_LBU             : std_logic_vector(2 downto 0) := "100";
    constant FUNCT3_LHU             : std_logic_vector(2 downto 0) := "101";

    -- -------------------------------------------------------------------------
    -- Funct3 Constants for Stores (OPC_STORE)
    -- -------------------------------------------------------------------------
    constant FUNCT3_SB              : std_logic_vector(2 downto 0) := "000";
    constant FUNCT3_SH              : std_logic_vector(2 downto 0) := "001";
    constant FUNCT3_SW              : std_logic_vector(2 downto 0) := "010";

    -- -------------------------------------------------------------------------
    -- Funct3 Constants for ALU Operations (OPC_OP / OPC_OP_IMM)
    -- -------------------------------------------------------------------------
    constant FUNCT3_ADD_SUB         : std_logic_vector(2 downto 0) := "000";
    constant FUNCT3_SLL             : std_logic_vector(2 downto 0) := "001";
    constant FUNCT3_SLT             : std_logic_vector(2 downto 0) := "010";
    constant FUNCT3_SLTU            : std_logic_vector(2 downto 0) := "011";
    constant FUNCT3_XOR             : std_logic_vector(2 downto 0) := "100";
    constant FUNCT3_SRL_SRA         : std_logic_vector(2 downto 0) := "101";
    constant FUNCT3_OR              : std_logic_vector(2 downto 0) := "110";
    constant FUNCT3_AND             : std_logic_vector(2 downto 0) := "111";

    -- -------------------------------------------------------------------------
    -- Funct7 Constants for ALU Operations
    -- -------------------------------------------------------------------------
    constant FUNCT7_BASE            : std_logic_vector(6 downto 0) := "0000000";
    constant FUNCT7_ALT             : std_logic_vector(6 downto 0) := "0100000"; -- SUB / SRA
    constant FUNCT7_MULDIV          : std_logic_vector(6 downto 0) := "0000001"; -- RV32M extension

    -- -------------------------------------------------------------------------
    -- Funct3 Constants for RV32M Extension (FUNCT7 = FUNCT7_MULDIV)
    -- -------------------------------------------------------------------------
    constant FUNCT3_MUL             : std_logic_vector(2 downto 0) := "000";
    constant FUNCT3_MULH            : std_logic_vector(2 downto 0) := "001";
    constant FUNCT3_MULHSU          : std_logic_vector(2 downto 0) := "010";
    constant FUNCT3_MULHU           : std_logic_vector(2 downto 0) := "011";
    constant FUNCT3_DIV             : std_logic_vector(2 downto 0) := "100";
    constant FUNCT3_DIVU            : std_logic_vector(2 downto 0) := "101";
    constant FUNCT3_REM             : std_logic_vector(2 downto 0) := "110";
    constant FUNCT3_REMU            : std_logic_vector(2 downto 0) := "111";

    -- -------------------------------------------------------------------------
    -- Funct3 Constants for CSR Operations (OPC_SYSTEM)
    -- -------------------------------------------------------------------------
    constant FUNCT3_PRIV            : std_logic_vector(2 downto 0) := "000";
    constant FUNCT3_CSRRW           : std_logic_vector(2 downto 0) := "001";
    constant FUNCT3_CSRRS           : std_logic_vector(2 downto 0) := "010";
    constant FUNCT3_CSRRC           : std_logic_vector(2 downto 0) := "011";
    constant FUNCT3_CSRRWI          : std_logic_vector(2 downto 0) := "101";
    constant FUNCT3_CSRRSI          : std_logic_vector(2 downto 0) := "110";
    constant FUNCT3_CSRRCI          : std_logic_vector(2 downto 0) := "111";

    -- -------------------------------------------------------------------------
    -- Privileged System Sub-Operations (OPC_SYSTEM with FUNCT3_PRIV)
    -- -------------------------------------------------------------------------
    constant FUNCT12_ECALL          : std_logic_vector(11 downto 0) := "000000000000";
    constant FUNCT12_EBREAK         : std_logic_vector(11 downto 0) := "000000000001";
    constant FUNCT12_MRET           : std_logic_vector(11 downto 0) := "001100000010";
    constant FUNCT12_WFI            : std_logic_vector(11 downto 0) := "000100000101";

    -- -------------------------------------------------------------------------
    -- CSR Addresses
    -- -------------------------------------------------------------------------
    constant CSR_FFLAGS             : std_logic_vector(11 downto 0) := x"001";
    constant CSR_FRM                : std_logic_vector(11 downto 0) := x"002";
    constant CSR_FCSR               : std_logic_vector(11 downto 0) := x"003";

    constant CSR_MSTATUS            : std_logic_vector(11 downto 0) := x"300";
    constant CSR_MISA               : std_logic_vector(11 downto 0) := x"301";
    constant CSR_MIE                : std_logic_vector(11 downto 0) := x"304";
    constant CSR_MTVEC              : std_logic_vector(11 downto 0) := x"305";

    constant CSR_MSCRATCH           : std_logic_vector(11 downto 0) := x"340";
    constant CSR_MEPC               : std_logic_vector(11 downto 0) := x"341";
    constant CSR_MCAUSE             : std_logic_vector(11 downto 0) := x"342";
    constant CSR_MTVAL              : std_logic_vector(11 downto 0) := x"343";
    constant CSR_MIP                : std_logic_vector(11 downto 0) := x"344";

    constant CSR_MCYCLE             : std_logic_vector(11 downto 0) := x"B00";
    constant CSR_MCYCLEH            : std_logic_vector(11 downto 0) := x"B80";
    constant CSR_MINSTRET           : std_logic_vector(11 downto 0) := x"B02";
    constant CSR_MINSTRETH          : std_logic_vector(11 downto 0) := x"B82";

    constant CSR_CYCLE              : std_logic_vector(11 downto 0) := x"C00";
    constant CSR_TIME               : std_logic_vector(11 downto 0) := x"C01";
    constant CSR_INSTRET            : std_logic_vector(11 downto 0) := x"C02";

    constant CSR_MVENDORID          : std_logic_vector(11 downto 0) := x"F11";
    constant CSR_MARCHID            : std_logic_vector(11 downto 0) := x"F12";
    constant CSR_MIMPID             : std_logic_vector(11 downto 0) := x"F13";
    constant CSR_MHARTID            : std_logic_vector(11 downto 0) := x"F14";

    -- -------------------------------------------------------------------------
    -- Exception Causes (mcause values when MSB = 0)
    -- -------------------------------------------------------------------------
    constant CAUSE_INSTR_ADDR_MISALIGN : std_logic_vector(4 downto 0) := "00000"; -- 0
    constant CAUSE_INSTR_ACCESS_FAULT  : std_logic_vector(4 downto 0) := "00001"; -- 1
    constant CAUSE_ILLEGAL_INSTR       : std_logic_vector(4 downto 0) := "00010"; -- 2
    constant CAUSE_BREAKPOINT          : std_logic_vector(4 downto 0) := "00011"; -- 3
    constant CAUSE_LOAD_ADDR_MISALIGN  : std_logic_vector(4 downto 0) := "00100"; -- 4
    constant CAUSE_LOAD_ACCESS_FAULT   : std_logic_vector(4 downto 0) := "00101"; -- 5
    constant CAUSE_STORE_ADDR_MISALIGN : std_logic_vector(4 downto 0) := "00110"; -- 6
    constant CAUSE_STORE_ACCESS_FAULT  : std_logic_vector(4 downto 0) := "00111"; -- 7
    constant CAUSE_ECALL_U_MODE        : std_logic_vector(4 downto 0) := "01000"; -- 8
    constant CAUSE_ECALL_M_MODE        : std_logic_vector(4 downto 0) := "01011"; -- 11

    -- -------------------------------------------------------------------------
    -- Interrupt Causes (mcause values when MSB = 1)
    -- -------------------------------------------------------------------------
    constant INT_CAUSE_M_SOFTWARE      : std_logic_vector(3 downto 0) := "0011"; -- 3
    constant INT_CAUSE_M_TIMER         : std_logic_vector(3 downto 0) := "0111"; -- 7
    constant INT_CAUSE_M_EXTERNAL      : std_logic_vector(3 downto 0) := "1011"; -- 11

end package talos_rv32_pkg;
