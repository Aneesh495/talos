-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Decode: Full RV32IMF Instruction Decoder
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_rv32_pkg.all;

entity talos_decoder is
    port (
        instr_valid : in  std_logic;
        pc          : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        instr       : in  std_logic_vector(INSTR_WIDTH-1 downto 0);
        pred_taken  : in  std_logic;
        pred_target : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        dec_pkt     : out decode_pkt_t
    );
end entity talos_decoder;

architecture rtl of talos_decoder is

    signal imm_i : std_logic_vector(XLEN-1 downto 0);
    signal imm_s : std_logic_vector(XLEN-1 downto 0);
    signal imm_b : std_logic_vector(XLEN-1 downto 0);
    signal imm_u : std_logic_vector(XLEN-1 downto 0);
    signal imm_j : std_logic_vector(XLEN-1 downto 0);
    signal imm_z : std_logic_vector(XLEN-1 downto 0);

begin

    u_imm_gen : entity work.talos_imm_gen
        port map (
            instr => instr,
            imm_i => imm_i,
            imm_s => imm_s,
            imm_b => imm_b,
            imm_u => imm_u,
            imm_j => imm_j,
            imm_z => imm_z
        );

    process(instr_valid, pc, instr, pred_taken, pred_target,
            imm_i, imm_s, imm_b, imm_u, imm_j, imm_z)
        variable pkt    : decode_pkt_t;
        variable opcode : std_logic_vector(6 downto 0);
        variable funct3 : std_logic_vector(2 downto 0);
        variable funct7 : std_logic_vector(6 downto 0);
        variable rd     : std_logic_vector(4 downto 0);
        variable rs1    : std_logic_vector(4 downto 0);
        variable rs2    : std_logic_vector(4 downto 0);
    begin
        pkt := DECODE_PKT_ZERO;

        if instr_valid = '1' then
            opcode := instr(6 downto 0);
            funct3 := instr(14 downto 12);
            funct7 := instr(31 downto 25);
            rd     := instr(11 downto 7);
            rs1    := instr(19 downto 15);
            rs2    := instr(24 downto 20);

            pkt.valid       := '1';
            pkt.pc          := pc;
            pkt.instr       := instr;
            pkt.rs1_arch    := rs1;
            pkt.rs2_arch    := rs2;
            pkt.rs3_arch    := instr(31 downto 27);
            pkt.rd_arch     := rd;
            pkt.pred_taken  := pred_taken;
            pkt.pred_target := pred_target;

            case opcode is

                -- -------------------------------------------------------------
                -- Integer Register-Immediate ALU Operations (OPC_OP_IMM)
                -- -------------------------------------------------------------
                when OPC_OP_IMM =>
                    pkt.fu_type  := FU_ALU0;
                    pkt.use_imm  := '1';
                    pkt.imm      := imm_i;
                    pkt.has_dest := bool_to_sl(rd /= "00000");

                    case funct3 is
                        when FUNCT3_ADD_SUB => pkt.alu_op := ALU_ADD;
                        when FUNCT3_SLL     => pkt.alu_op := ALU_SLL;
                        when FUNCT3_SLT     => pkt.alu_op := ALU_SLT;
                        when FUNCT3_SLTU    => pkt.alu_op := ALU_SLTU;
                        when FUNCT3_XOR     => pkt.alu_op := ALU_XOR;
                        when FUNCT3_SRL_SRA =>
                            if funct7(5) = '1' then
                                pkt.alu_op := ALU_SRA;
                            else
                                pkt.alu_op := ALU_SRL;
                            end if;
                        when FUNCT3_OR      => pkt.alu_op := ALU_OR;
                        when FUNCT3_AND     => pkt.alu_op := ALU_AND;
                        when others         => pkt.illegal_op := '1';
                    end case;

                -- -------------------------------------------------------------
                -- Integer Register-Register Operations (OPC_OP)
                -- -------------------------------------------------------------
                when OPC_OP =>
                    pkt.has_dest := bool_to_sl(rd /= "00000");

                    if funct7 = FUNCT7_MULDIV then
                        -- RV32M Multiply/Divide Extension
                        pkt.fu_type := FU_MULDIV;
                        case funct3 is
                            when FUNCT3_MUL    => pkt.md_op := MD_MUL;
                            when FUNCT3_MULH   => pkt.md_op := MD_MULH;
                            when FUNCT3_MULHSU => pkt.md_op := MD_MULHSU;
                            when FUNCT3_MULHU  => pkt.md_op := MD_MULHU;
                            when FUNCT3_DIV    => pkt.md_op := MD_DIV;
                            when FUNCT3_DIVU   => pkt.md_op := MD_DIVU;
                            when FUNCT3_REM    => pkt.md_op := MD_REM;
                            when FUNCT3_REMU   => pkt.md_op := MD_REMU;
                            when others        => pkt.illegal_op := '1';
                        end case;
                    else
                        -- Standard Base ALU
                        pkt.fu_type := FU_ALU0;
                        case funct3 is
                            when FUNCT3_ADD_SUB =>
                                if funct7(5) = '1' then
                                    pkt.alu_op := ALU_SUB;
                                else
                                    pkt.alu_op := ALU_ADD;
                                end if;
                            when FUNCT3_SLL     => pkt.alu_op := ALU_SLL;
                            when FUNCT3_SLT     => pkt.alu_op := ALU_SLT;
                            when FUNCT3_SLTU    => pkt.alu_op := ALU_SLTU;
                            when FUNCT3_XOR     => pkt.alu_op := ALU_XOR;
                            when FUNCT3_SRL_SRA =>
                                if funct7(5) = '1' then
                                    pkt.alu_op := ALU_SRA;
                                else
                                    pkt.alu_op := ALU_SRL;
                                end if;
                            when FUNCT3_OR      => pkt.alu_op := ALU_OR;
                            when FUNCT3_AND     => pkt.alu_op := ALU_AND;
                            when others         => pkt.illegal_op := '1';
                        end case;
                    end if;

                -- -------------------------------------------------------------
                -- Upper Immediates (LUI, AUIPC)
                -- -------------------------------------------------------------
                when OPC_LUI =>
                    pkt.fu_type  := FU_ALU0;
                    pkt.alu_op   := ALU_LUI;
                    pkt.use_imm  := '1';
                    pkt.imm      := imm_u;
                    pkt.has_dest := bool_to_sl(rd /= "00000");

                when OPC_AUIPC =>
                    pkt.fu_type  := FU_ALU0;
                    pkt.alu_op   := ALU_AUIPC;
                    pkt.use_imm  := '1';
                    pkt.imm      := imm_u;
                    pkt.has_dest := bool_to_sl(rd /= "00000");

                -- -------------------------------------------------------------
                -- Control Transfer: Conditional Branches (OPC_BRANCH)
                -- -------------------------------------------------------------
                when OPC_BRANCH =>
                    pkt.fu_type   := FU_BRANCH;
                    pkt.is_branch := '1';
                    pkt.use_imm   := '1';
                    pkt.imm       := imm_b;

                    case funct3 is
                        when FUNCT3_BEQ  => pkt.br_op := BR_BEQ;
                        when FUNCT3_BNE  => pkt.br_op := BR_BNE;
                        when FUNCT3_BLT  => pkt.br_op := BR_BLT;
                        when FUNCT3_BGE  => pkt.br_op := BR_BGE;
                        when FUNCT3_BLTU => pkt.br_op := BR_BLTU;
                        when FUNCT3_BGEU => pkt.br_op := BR_BGEU;
                        when others      => pkt.illegal_op := '1';
                    end case;

                -- -------------------------------------------------------------
                -- Control Transfer: Unconditional Jumps (JAL, JALR)
                -- -------------------------------------------------------------
                when OPC_JAL =>
                    pkt.fu_type   := FU_BRANCH;
                    pkt.br_op     := BR_JAL;
                    pkt.is_jump   := '1';
                    pkt.use_imm   := '1';
                    pkt.imm       := imm_j;
                    pkt.has_dest  := bool_to_sl(rd /= "00000");

                when OPC_JALR =>
                    pkt.fu_type   := FU_BRANCH;
                    pkt.br_op     := BR_JALR;
                    pkt.is_jump   := '1';
                    pkt.use_imm   := '1';
                    pkt.imm       := imm_i;
                    pkt.has_dest  := bool_to_sl(rd /= "00000");

                -- -------------------------------------------------------------
                -- Load Operations (OPC_LOAD)
                -- -------------------------------------------------------------
                when OPC_LOAD =>
                    pkt.fu_type  := FU_MEM;
                    pkt.is_load  := '1';
                    pkt.use_imm  := '1';
                    pkt.imm      := imm_i;
                    pkt.has_dest := bool_to_sl(rd /= "00000");

                    case funct3 is
                        when FUNCT3_LB  => pkt.mem_op := MEM_LB;
                        when FUNCT3_LH  => pkt.mem_op := MEM_LH;
                        when FUNCT3_LW  => pkt.mem_op := MEM_LW;
                        when FUNCT3_LBU => pkt.mem_op := MEM_LBU;
                        when FUNCT3_LHU => pkt.mem_op := MEM_LHU;
                        when others     => pkt.illegal_op := '1';
                    end case;

                -- -------------------------------------------------------------
                -- Store Operations (OPC_STORE)
                -- -------------------------------------------------------------
                when OPC_STORE =>
                    pkt.fu_type  := FU_MEM;
                    pkt.is_store := '1';
                    pkt.use_imm  := '1';
                    pkt.imm      := imm_s;

                    case funct3 is
                        when FUNCT3_SB => pkt.mem_op := MEM_SB;
                        when FUNCT3_SH => pkt.mem_op := MEM_SH;
                        when FUNCT3_SW => pkt.mem_op := MEM_SW;
                        when others    => pkt.illegal_op := '1';
                    end case;

                -- -------------------------------------------------------------
                -- Privileged System & CSR Operations (OPC_SYSTEM)
                -- -------------------------------------------------------------
                when OPC_SYSTEM =>
                    pkt.fu_type  := FU_CSR;
                    pkt.is_csr   := '1';
                    pkt.has_dest := bool_to_sl(rd /= "00000");

                    case funct3 is
                        when FUNCT3_PRIV =>
                            -- ECALL, EBREAK, MRET
                            pkt.use_imm := '0';
                        when FUNCT3_CSRRW | FUNCT3_CSRRS | FUNCT3_CSRRC =>
                            pkt.use_imm := '0';
                        when FUNCT3_CSRRWI | FUNCT3_CSRRSI | FUNCT3_CSRRCI =>
                            pkt.use_imm := '1';
                            pkt.imm     := imm_z;
                        when others =>
                            pkt.illegal_op := '1';
                    end case;

                -- -------------------------------------------------------------
                -- Memory Fences (OPC_MISC_MEM)
                -- -------------------------------------------------------------
                when OPC_MISC_MEM =>
                    pkt.fu_type := FU_ALU0;
                    pkt.alu_op  := ALU_ADD; -- Treat as NOP in execution

                -- -------------------------------------------------------------
                -- Floating-Point Operations (OPC_OP_FP, OPC_LOAD_FP, OPC_STORE_FP)
                -- -------------------------------------------------------------
                when OPC_OP_FP =>
                    pkt.fu_type  := FU_FPU;
                    pkt.is_fpu   := '1';
                    pkt.has_dest := '1';
                    case funct7(6 downto 2) is
                        when "00000" => pkt.fpu_op := FPU_ADD;
                        when "00001" => pkt.fpu_op := FPU_SUB;
                        when "00010" => pkt.fpu_op := FPU_MUL;
                        when "00011" => pkt.fpu_op := FPU_DIV;
                        when "01011" => pkt.fpu_op := FPU_SQRT;
                        when "11000" => pkt.fpu_op := FPU_CVT_W_S;
                        when "11010" => pkt.fpu_op := FPU_CVT_S_W;
                        when "10100" =>
                            case funct3 is
                                when "010" => pkt.fpu_op := FPU_FEQ;
                                when "001" => pkt.fpu_op := FPU_FLT;
                                when "000" => pkt.fpu_op := FPU_FLE;
                                when others => pkt.illegal_op := '1';
                            end case;
                        when others => pkt.illegal_op := '1';
                    end case;

                when OPC_LOAD_FP =>
                    pkt.fu_type  := FU_MEM;
                    pkt.is_load  := '1';
                    pkt.is_fpu   := '1';
                    pkt.mem_op   := MEM_LW;
                    pkt.use_imm  := '1';
                    pkt.imm      := imm_i;
                    pkt.has_dest := '1';

                when OPC_STORE_FP =>
                    pkt.fu_type  := FU_MEM;
                    pkt.is_store := '1';
                    pkt.is_fpu   := '1';
                    pkt.mem_op   := MEM_SW;
                    pkt.use_imm  := '1';
                    pkt.imm      := imm_s;

                when others =>
                    pkt.illegal_op := '1';

            end case;
        end if;

        dec_pkt <= pkt;
    end process;

end architecture rtl;
