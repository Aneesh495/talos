// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Golden Emulator: High-Performance RV32IMF Disassembler Implementation
// Standard: C++20
// ==============================================================================

#include "talos_disasm.hpp"
#include <cstdio>
#include <sstream>
#include <iomanip>

namespace talos {

static const char* const ABI_INT_REGS[32] = {
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0",   "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6",   "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8",   "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

static const char* const ABI_FP_REGS[32] = {
    "ft0", "ft1", "ft2",  "ft3",  "ft4", "ft5", "ft6",  "ft7",
    "fs0", "fs1", "fa0",  "fa1",  "fa2", "fa3", "fa4",  "fa5",
    "fa6", "fa7", "fs2",  "fs3",  "fs4", "fs5", "fs6",  "fs7",
    "fs8", "fs9", "fs10", "fs11", "ft8", "ft9", "ft10", "ft11"
};

const char* Disassembler::reg_name(uint32_t r) {
    if (r < 32) return ABI_INT_REGS[r];
    return "unknown";
}

const char* Disassembler::fp_reg_name(uint32_t r) {
    if (r < 32) return ABI_FP_REGS[r];
    return "unknown";
}

const char* Disassembler::csr_name(uint32_t csr) {
    switch (csr) {
        case 0x300: return "mstatus";
        case 0x301: return "misa";
        case 0x302: return "medeleg";
        case 0x303: return "mideleg";
        case 0x304: return "mie";
        case 0x305: return "mtvec";
        case 0x340: return "mscratch";
        case 0x341: return "mepc";
        case 0x342: return "mcause";
        case 0x343: return "mtval";
        case 0x344: return "mip";
        case 0xB00: return "mcycle";
        case 0xB02: return "minstret";
        case 0xB80: return "mcycleh";
        case 0xB82: return "minstreth";
        default:    return "unknown_csr";
    }
}

std::string Disassembler::disassemble(uint32_t pc, uint32_t instr) {
    uint32_t opcode = instr & 0x7F;
    uint32_t rd     = (instr >> 7) & 0x1F;
    uint32_t funct3 = (instr >> 12) & 0x07;
    uint32_t rs1    = (instr >> 15) & 0x1F;
    uint32_t rs2    = (instr >> 20) & 0x1F;
    uint32_t funct7 = (instr >> 25) & 0x7F;

    // Immediate decoding
    int32_t imm_i = static_cast<int32_t>(instr) >> 20;
    int32_t imm_s = ((static_cast<int32_t>(instr) >> 25) << 5) | static_cast<int32_t>((instr >> 7) & 0x1F);
    if (imm_s & 0x800) imm_s |= 0xFFFFF000;

    int32_t imm_b = (((static_cast<int32_t>(instr) >> 31) & 0x1) << 12) |
                    (((static_cast<int32_t>(instr) >> 7) & 0x1) << 11) |
                    (((static_cast<int32_t>(instr) >> 25) & 0x3F) << 5) |
                    (((static_cast<int32_t>(instr) >> 8) & 0xF) << 1);
    if (imm_b & 0x1000) imm_b |= 0xFFFFE000;

    uint32_t imm_u = instr & 0xFFFFF000;

    int32_t imm_j = (((static_cast<int32_t>(instr) >> 31) & 0x1) << 20) |
                    (((static_cast<int32_t>(instr) >> 12) & 0xFF) << 12) |
                    (((static_cast<int32_t>(instr) >> 20) & 0x1) << 11) |
                    (((static_cast<int32_t>(instr) >> 21) & 0x3FF) << 1);
    if (imm_j & 0x100000) imm_j |= 0xFFE00000;

    char buf[128];

    switch (opcode) {
        case 0x37: // LUI
            std::snprintf(buf, sizeof(buf), "lui      %s, 0x%x", reg_name(rd), imm_u >> 12);
            return buf;

        case 0x17: // AUIPC
            std::snprintf(buf, sizeof(buf), "auipc    %s, 0x%x", reg_name(rd), imm_u >> 12);
            return buf;

        case 0x6F: // JAL
            if (rd == 0) {
                std::snprintf(buf, sizeof(buf), "j        0x%08x", pc + imm_j);
            } else if (rd == 1) {
                std::snprintf(buf, sizeof(buf), "jal      0x%08x", pc + imm_j);
            } else {
                std::snprintf(buf, sizeof(buf), "jal      %s, 0x%08x", reg_name(rd), pc + imm_j);
            }
            return buf;

        case 0x67: // JALR
            if (rd == 0 && rs1 == 1 && imm_i == 0) {
                return "ret";
            }
            if (rd == 0) {
                std::snprintf(buf, sizeof(buf), "jr       %s", reg_name(rs1));
                return buf;
            }
            std::snprintf(buf, sizeof(buf), "jalr     %s, %d(%s)", reg_name(rd), imm_i, reg_name(rs1));
            return buf;

        case 0x63: // Branches
            switch (funct3) {
                case 0x0:
                    if (rs2 == 0) {
                        std::snprintf(buf, sizeof(buf), "beqz     %s, 0x%08x", reg_name(rs1), pc + imm_b);
                    } else {
                        std::snprintf(buf, sizeof(buf), "beq      %s, %s, 0x%08x", reg_name(rs1), reg_name(rs2), pc + imm_b);
                    }
                    return buf;
                case 0x1:
                    if (rs2 == 0) {
                        std::snprintf(buf, sizeof(buf), "bnez     %s, 0x%08x", reg_name(rs1), pc + imm_b);
                    } else {
                        std::snprintf(buf, sizeof(buf), "bne      %s, %s, 0x%08x", reg_name(rs1), reg_name(rs2), pc + imm_b);
                    }
                    return buf;
                case 0x4: std::snprintf(buf, sizeof(buf), "blt      %s, %s, 0x%08x", reg_name(rs1), reg_name(rs2), pc + imm_b); return buf;
                case 0x5: std::snprintf(buf, sizeof(buf), "bge      %s, %s, 0x%08x", reg_name(rs1), reg_name(rs2), pc + imm_b); return buf;
                case 0x6: std::snprintf(buf, sizeof(buf), "bltu     %s, %s, 0x%08x", reg_name(rs1), reg_name(rs2), pc + imm_b); return buf;
                case 0x7: std::snprintf(buf, sizeof(buf), "bgeu     %s, %s, 0x%08x", reg_name(rs1), reg_name(rs2), pc + imm_b); return buf;
                default: break;
            }
            break;

        case 0x03: // Loads
            switch (funct3) {
                case 0x0: std::snprintf(buf, sizeof(buf), "lb       %s, %d(%s)", reg_name(rd), imm_i, reg_name(rs1)); return buf;
                case 0x1: std::snprintf(buf, sizeof(buf), "lh       %s, %d(%s)", reg_name(rd), imm_i, reg_name(rs1)); return buf;
                case 0x2: std::snprintf(buf, sizeof(buf), "lw       %s, %d(%s)", reg_name(rd), imm_i, reg_name(rs1)); return buf;
                case 0x4: std::snprintf(buf, sizeof(buf), "lbu      %s, %d(%s)", reg_name(rd), imm_i, reg_name(rs1)); return buf;
                case 0x5: std::snprintf(buf, sizeof(buf), "lhu      %s, %d(%s)", reg_name(rd), imm_i, reg_name(rs1)); return buf;
                default: break;
            }
            break;

        case 0x23: // Stores
            switch (funct3) {
                case 0x0: std::snprintf(buf, sizeof(buf), "sb       %s, %d(%s)", reg_name(rs2), imm_s, reg_name(rs1)); return buf;
                case 0x1: std::snprintf(buf, sizeof(buf), "sh       %s, %d(%s)", reg_name(rs2), imm_s, reg_name(rs1)); return buf;
                case 0x2: std::snprintf(buf, sizeof(buf), "sw       %s, %d(%s)", reg_name(rs2), imm_s, reg_name(rs1)); return buf;
                default: break;
            }
            break;

        case 0x13: // ALU Immediate
            if (instr == 0x00000013) return "nop";
            switch (funct3) {
                case 0x0:
                    if (rs1 == 0) {
                        std::snprintf(buf, sizeof(buf), "li       %s, %d", reg_name(rd), imm_i);
                    } else if (imm_i == 0) {
                        std::snprintf(buf, sizeof(buf), "mv       %s, %s", reg_name(rd), reg_name(rs1));
                    } else {
                        std::snprintf(buf, sizeof(buf), "addi     %s, %s, %d", reg_name(rd), reg_name(rs1), imm_i);
                    }
                    return buf;
                case 0x1: std::snprintf(buf, sizeof(buf), "slli     %s, %s, %u", reg_name(rd), reg_name(rs1), imm_i & 0x1F); return buf;
                case 0x2: std::snprintf(buf, sizeof(buf), "slti     %s, %s, %d", reg_name(rd), reg_name(rs1), imm_i); return buf;
                case 0x3: std::snprintf(buf, sizeof(buf), "sltiu    %s, %s, %u", reg_name(rd), reg_name(rs1), static_cast<uint32_t>(imm_i)); return buf;
                case 0x4:
                    if (imm_i == -1) {
                        std::snprintf(buf, sizeof(buf), "not      %s, %s", reg_name(rd), reg_name(rs1));
                    } else {
                        std::snprintf(buf, sizeof(buf), "xori     %s, %s, %d", reg_name(rd), reg_name(rs1), imm_i);
                    }
                    return buf;
                case 0x5:
                    if ((imm_i >> 5) & 0x20) {
                        std::snprintf(buf, sizeof(buf), "srai     %s, %s, %u", reg_name(rd), reg_name(rs1), imm_i & 0x1F);
                    } else {
                        std::snprintf(buf, sizeof(buf), "srli     %s, %s, %u", reg_name(rd), reg_name(rs1), imm_i & 0x1F);
                    }
                    return buf;
                case 0x6: std::snprintf(buf, sizeof(buf), "ori      %s, %s, %d", reg_name(rd), reg_name(rs1), imm_i); return buf;
                case 0x7: std::snprintf(buf, sizeof(buf), "andi     %s, %s, %d", reg_name(rd), reg_name(rs1), imm_i); return buf;
                default: break;
            }
            break;

        case 0x33: // ALU Register and M-Extension
            if (funct7 == 0x01) { // M Extension
                switch (funct3) {
                    case 0x0: std::snprintf(buf, sizeof(buf), "mul      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x1: std::snprintf(buf, sizeof(buf), "mulh     %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x2: std::snprintf(buf, sizeof(buf), "mulhsu   %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x3: std::snprintf(buf, sizeof(buf), "mulhu    %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x4: std::snprintf(buf, sizeof(buf), "div      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x5: std::snprintf(buf, sizeof(buf), "divu     %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x6: std::snprintf(buf, sizeof(buf), "rem      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x7: std::snprintf(buf, sizeof(buf), "remu     %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    default: break;
                }
            } else {
                switch (funct3) {
                    case 0x0:
                        if (funct7 == 0x20) {
                            if (rs1 == 0) {
                                std::snprintf(buf, sizeof(buf), "neg      %s, %s", reg_name(rd), reg_name(rs2));
                            } else {
                                std::snprintf(buf, sizeof(buf), "sub      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                            }
                        } else {
                            std::snprintf(buf, sizeof(buf), "add      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        }
                        return buf;
                    case 0x1: std::snprintf(buf, sizeof(buf), "sll      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x2:
                        if (rs2 == 0) {
                            std::snprintf(buf, sizeof(buf), "sltz     %s, %s", reg_name(rd), reg_name(rs1));
                        } else {
                            std::snprintf(buf, sizeof(buf), "slt      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        }
                        return buf;
                    case 0x3: std::snprintf(buf, sizeof(buf), "sltu     %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x4: std::snprintf(buf, sizeof(buf), "xor      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x5:
                        if (funct7 == 0x20) {
                            std::snprintf(buf, sizeof(buf), "sra      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        } else {
                            std::snprintf(buf, sizeof(buf), "srl      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        }
                        return buf;
                    case 0x6: std::snprintf(buf, sizeof(buf), "or       %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    case 0x7: std::snprintf(buf, sizeof(buf), "and      %s, %s, %s", reg_name(rd), reg_name(rs1), reg_name(rs2)); return buf;
                    default: break;
                }
            }
            break;

        case 0x07: // FLW
            std::snprintf(buf, sizeof(buf), "flw      %s, %d(%s)", fp_reg_name(rd), imm_i, reg_name(rs1));
            return buf;

        case 0x27: // FSW
            std::snprintf(buf, sizeof(buf), "fsw      %s, %d(%s)", fp_reg_name(rs2), imm_s, reg_name(rs1));
            return buf;

        case 0x53: // FPU Operations
            switch (funct7) {
                case 0x00: std::snprintf(buf, sizeof(buf), "fadd.s   %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                case 0x04: std::snprintf(buf, sizeof(buf), "fsub.s   %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                case 0x08: std::snprintf(buf, sizeof(buf), "fmul.s   %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                case 0x0C: std::snprintf(buf, sizeof(buf), "fdiv.s   %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                case 0x2C: std::snprintf(buf, sizeof(buf), "fsqrt.s  %s, %s", fp_reg_name(rd), fp_reg_name(rs1)); return buf;
                case 0x10:
                    switch (funct3) {
                        case 0x0: std::snprintf(buf, sizeof(buf), "fsgnj.s  %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                        case 0x1: std::snprintf(buf, sizeof(buf), "fsgnjn.s %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                        case 0x2: std::snprintf(buf, sizeof(buf), "fsgnjx.s %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                        default: break;
                    }
                    break;
                case 0x14:
                    if (funct3 == 0x0) {
                        std::snprintf(buf, sizeof(buf), "fmin.s   %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2));
                    } else {
                        std::snprintf(buf, sizeof(buf), "fmax.s   %s, %s, %s", fp_reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2));
                    }
                    return buf;
                case 0x60:
                    if (rs2 == 0) {
                        std::snprintf(buf, sizeof(buf), "fcvt.w.s %s, %s", reg_name(rd), fp_reg_name(rs1));
                    } else {
                        std::snprintf(buf, sizeof(buf), "fcvt.wu.s %s, %s", reg_name(rd), fp_reg_name(rs1));
                    }
                    return buf;
                case 0x70:
                    if (funct3 == 0x0) {
                        std::snprintf(buf, sizeof(buf), "fmv.x.w  %s, %s", reg_name(rd), fp_reg_name(rs1));
                    } else {
                        std::snprintf(buf, sizeof(buf), "fclass.s %s, %s", reg_name(rd), fp_reg_name(rs1));
                    }
                    return buf;
                case 0x50:
                    switch (funct3) {
                        case 0x0: std::snprintf(buf, sizeof(buf), "fle.s    %s, %s, %s", reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                        case 0x1: std::snprintf(buf, sizeof(buf), "flt.s    %s, %s, %s", reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                        case 0x2: std::snprintf(buf, sizeof(buf), "feq.s    %s, %s, %s", reg_name(rd), fp_reg_name(rs1), fp_reg_name(rs2)); return buf;
                        default: break;
                    }
                    break;
                case 0x68:
                    if (rs2 == 0) {
                        std::snprintf(buf, sizeof(buf), "fcvt.s.w %s, %s", fp_reg_name(rd), reg_name(rs1));
                    } else {
                        std::snprintf(buf, sizeof(buf), "fcvt.s.wu %s, %s", fp_reg_name(rd), reg_name(rs1));
                    }
                    return buf;
                case 0x78:
                    std::snprintf(buf, sizeof(buf), "fmv.w.x  %s, %s", fp_reg_name(rd), reg_name(rs1));
                    return buf;
                default: break;
            }
            break;

        case 0x73: // System / Privileged
            if (funct3 == 0x0) {
                if (imm_i == 0x000) return "ecall";
                if (imm_i == 0x001) return "ebreak";
                if (imm_i == 0x302) return "mret";
                if (imm_i == 0x105) return "wfi";
            } else {
                uint32_t csr_addr = (instr >> 20) & 0xFFF;
                const char* cname = csr_name(csr_addr);
                switch (funct3) {
                    case 0x1: std::snprintf(buf, sizeof(buf), "csrrw    %s, %s, %s", reg_name(rd), cname, reg_name(rs1)); return buf;
                    case 0x2:
                        if (rs1 == 0) {
                            std::snprintf(buf, sizeof(buf), "csrr     %s, %s", reg_name(rd), cname);
                        } else {
                            std::snprintf(buf, sizeof(buf), "csrrs    %s, %s, %s", reg_name(rd), cname, reg_name(rs1));
                        }
                        return buf;
                    case 0x3: std::snprintf(buf, sizeof(buf), "csrrc    %s, %s, %s", reg_name(rd), cname, reg_name(rs1)); return buf;
                    case 0x5: std::snprintf(buf, sizeof(buf), "csrrwi   %s, %s, %u", reg_name(rd), cname, rs1); return buf;
                    case 0x6: std::snprintf(buf, sizeof(buf), "csrrsi   %s, %s, %u", reg_name(rd), cname, rs1); return buf;
                    case 0x7: std::snprintf(buf, sizeof(buf), "csrrci   %s, %s, %u", reg_name(rd), cname, rs1); return buf;
                    default: break;
                }
            }
            break;

        case 0x0F: // FENCE
            return "fence";

        default:
            break;
    }

    std::snprintf(buf, sizeof(buf), ".word    0x%08x", instr);
    return buf;
}

} // namespace talos
