-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: Branch Resolution, Target Validation, and Link Evaluator
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_branch_unit is
    port (
        br_op         : in  branch_op_t;
        src1          : in  std_logic_vector(XLEN-1 downto 0);
        src2          : in  std_logic_vector(XLEN-1 downto 0);
        pc            : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        imm           : in  std_logic_vector(XLEN-1 downto 0);
        pred_taken    : in  std_logic;
        pred_target   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Results
        actual_taken  : out std_logic;
        actual_target : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        link_val      : out std_logic_vector(XLEN-1 downto 0); -- Return address (pc + 4) for JAL/JALR
        mispredicted  : out std_logic;
        recovery_pc   : out std_logic_vector(ADDR_WIDTH-1 downto 0)
    );
end entity talos_branch_unit;

architecture rtl of talos_branch_unit is
begin

    process(br_op, src1, src2, pc, imm, pred_taken, pred_target)
        variable cond_taken   : boolean;
        variable target_calc  : std_logic_vector(ADDR_WIDTH-1 downto 0);
        variable seq_pc       : std_logic_vector(ADDR_WIDTH-1 downto 0);
        variable jalr_target  : unsigned(ADDR_WIDTH-1 downto 0);
        variable is_br        : boolean;
        variable is_jmp       : boolean;
        variable act_taken_sl : std_logic;
        variable mispred      : std_logic;
    begin
        cond_taken  := false;
        is_br       := false;
        is_jmp      := false;
        target_calc := (others => '0');
        seq_pc      := std_logic_vector(unsigned(pc) + 4);

        case br_op is
            when BR_BEQ =>
                is_br      := true;
                cond_taken := (src1 = src2);
                target_calc := std_logic_vector(unsigned(pc) + unsigned(imm));

            when BR_BNE =>
                is_br      := true;
                cond_taken := (src1 /= src2);
                target_calc := std_logic_vector(unsigned(pc) + unsigned(imm));

            when BR_BLT =>
                is_br      := true;
                cond_taken := (signed(src1) < signed(src2));
                target_calc := std_logic_vector(unsigned(pc) + unsigned(imm));

            when BR_BGE =>
                is_br      := true;
                cond_taken := (signed(src1) >= signed(src2));
                target_calc := std_logic_vector(unsigned(pc) + unsigned(imm));

            when BR_BLTU =>
                is_br      := true;
                cond_taken := (unsigned(src1) < unsigned(src2));
                target_calc := std_logic_vector(unsigned(pc) + unsigned(imm));

            when BR_BGEU =>
                is_br      := true;
                cond_taken := (unsigned(src1) >= unsigned(src2));
                target_calc := std_logic_vector(unsigned(pc) + unsigned(imm));

            when BR_JAL =>
                is_jmp      := true;
                cond_taken  := true;
                target_calc := std_logic_vector(unsigned(pc) + unsigned(imm));

            when BR_JALR =>
                is_jmp      := true;
                cond_taken  := true;
                jalr_target := unsigned(src1) + unsigned(imm);
                target_calc := std_logic_vector(jalr_target(ADDR_WIDTH-1 downto 1) & '0'); -- LSB cleared per RISC-V spec

            when others =>
                cond_taken  := false;
                target_calc := seq_pc;
        end case;

        act_taken_sl := bool_to_sl(cond_taken);

        -- Misprediction Detection:
        -- 1. Direction misprediction: predicted taken /= actually taken
        -- 2. Target address misprediction: predicted taken and actual taken, but target address differed
        mispred := '0';
        if is_br or is_jmp then
            if pred_taken /= act_taken_sl then
                mispred := '1';
            elsif act_taken_sl = '1' and pred_target /= target_calc then
                mispred := '1';
            end if;
        end if;

        actual_taken  <= act_taken_sl;
        actual_target <= target_calc;
        link_val      <= seq_pc;
        mispredicted  <= mispred;

        -- Calculate recovery PC for redirecting front-end
        if act_taken_sl = '1' then
            recovery_pc <= target_calc;
        else
            recovery_pc <= seq_pc;
        end if;
    end process;

end architecture rtl;
