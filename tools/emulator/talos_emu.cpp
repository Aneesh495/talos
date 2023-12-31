// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Golden Emulator: Architectural Simulator Engine Implementation
// Standard: C++20
// ==============================================================================

#include "talos_emu.hpp"
#include "talos_disasm.hpp"
#include "talos_elf.hpp"

#include <iostream>
#include <iomanip>
#include <cstring>
#include <cmath>
#include <bit>

namespace talos {

Emulator::Emulator() {
    rom_.resize(ROM_SIZE, 0);
    ram_.resize(RAM_SIZE, 0);
    reset();
}

void Emulator::reset(uint32_t start_pc) {
    pc_ = start_pc;
    regs_.fill(0);
    fpregs_.fill(0);
    mstatus_ = 0x1800; // MPP = 3
    misa_ = 0x40101124;
    mie_ = 0;
    mtvec_ = 0;
    mepc_ = 0;
    mcause_ = 0;
    mtval_ = 0;
    mip_ = 0;
    fcsr_ = 0;

    mtime_ = 0;
    mtimecmp_ = UINT64_MAX;

    cycles_ = 0;
    instret_ = 0;
    tohost_val_ = 0;

    branch_count_ = 0;
    branch_mispred_ = 0;
    load_count_ = 0;
    store_count_ = 0;
    fwd_count_ = 0;
}

bool Emulator::load_elf(const std::string& path) {
    uint32_t entry = 0;
    uint32_t tohost = 0;
    if (!ElfLoader::load_elf(path, ram_, RAM_BASE, entry, tohost)) {
        return false;
    }
    pc_ = entry;
    if (tohost != 0) {
        tohost_addr_ = tohost;
    }
    return true;
}

bool Emulator::load_hex(const std::string& path) {
    return ElfLoader::load_hex(path, ram_, RAM_BASE);
}

bool Emulator::load_bin(const std::string& path, uint32_t offset) {
    return ElfLoader::load_bin(path, ram_, RAM_BASE, offset);
}

void Emulator::enable_tracing(bool enable, const std::string& trace_path) {
    trace_enabled_ = enable;
    if (enable && !trace_path.empty()) {
        trace_file_.open(trace_path);
    }
}

uint8_t Emulator::read_u8(uint32_t addr) {
    if (addr >= ROM_BASE && addr < ROM_BASE + ROM_SIZE) {
        return rom_[addr - ROM_BASE];
    }
    if (addr >= RAM_BASE && addr < RAM_BASE + ram_.size()) {
        return ram_[addr - RAM_BASE];
    }
    if (addr >= UART_BASE && addr < UART_BASE + UART_SIZE) {
        uint32_t offset = addr - UART_BASE;
        if (offset == 5) {
            // Line Status Register (LSR): Transmitter empty & Holding register empty
            return 0x60;
        }
        return 0;
    }
    if (addr >= CLINT_BASE && addr < CLINT_BASE + CLINT_SIZE) {
        uint32_t offset = addr - CLINT_BASE;
        if (offset >= 0x4000 && offset < 0x4008) {
            return static_cast<uint8_t>((mtimecmp_ >> ((offset - 0x4000) * 8)) & 0xFF);
        }
        if (offset >= 0xBFF8 && offset < 0xC000) {
            return static_cast<uint8_t>((mtime_ >> ((offset - 0xBFF8) * 8)) & 0xFF);
        }
        return 0;
    }
    return 0;
}

uint16_t Emulator::read_u16(uint32_t addr) {
    uint16_t b0 = read_u8(addr);
    uint16_t b1 = read_u8(addr + 1);
    return static_cast<uint16_t>(b0 | (b1 << 8));
}

uint32_t Emulator::read_u32(uint32_t addr) {
    uint32_t b0 = read_u8(addr);
    uint32_t b1 = read_u8(addr + 1);
    uint32_t b2 = read_u8(addr + 2);
    uint32_t b3 = read_u8(addr + 3);
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

void Emulator::write_u8(uint32_t addr, uint8_t val) {
    if (addr >= RAM_BASE && addr < RAM_BASE + ram_.size()) {
        ram_[addr - RAM_BASE] = val;
        return;
    }
    if (addr >= UART_BASE && addr < UART_BASE + UART_SIZE) {
        uint32_t offset = addr - UART_BASE;
        if (offset == 0) {
            // UART TX Data Register: print character directly
            std::cout << static_cast<char>(val) << std::flush;
        }
        return;
    }
    if (addr >= CLINT_BASE && addr < CLINT_BASE + CLINT_SIZE) {
        uint32_t offset = addr - CLINT_BASE;
        if (offset >= 0x4000 && offset < 0x4008) {
            uint64_t shift = (offset - 0x4000) * 8;
            uint64_t mask = ~(0xFFULL << shift);
            mtimecmp_ = (mtimecmp_ & mask) | (static_cast<uint64_t>(val) << shift);
        }
    }
}

void Emulator::write_u16(uint32_t addr, uint16_t val) {
    write_u8(addr + 0, static_cast<uint8_t>(val & 0xFF));
    write_u8(addr + 1, static_cast<uint8_t>((val >> 8) & 0xFF));
}

void Emulator::write_u32(uint32_t addr, uint32_t val) {
    if (addr == tohost_addr_) {
        tohost_val_ = val;
    }
    write_u8(addr + 0, static_cast<uint8_t>(val & 0xFF));
    write_u8(addr + 1, static_cast<uint8_t>((val >> 8) & 0xFF));
    write_u8(addr + 2, static_cast<uint8_t>((val >> 16) & 0xFF));
    write_u8(addr + 3, static_cast<uint8_t>((val >> 24) & 0xFF));
}

void Emulator::update_timers() {
    mtime_++;
    if (mtime_ >= mtimecmp_) {
        mip_ |= (1 << 7); // MTIP (Machine Timer Interrupt Pending)
    } else {
        mip_ &= ~(1 << 7);
    }
}

void Emulator::handle_trap(uint32_t cause, uint32_t tval) {
    mepc_ = pc_;
    mcause_ = cause;
    mtval_ = tval;
    // Set MPIE to MIE, clear MIE
    uint32_t mstatus_mie = (mstatus_ >> 3) & 1;
    mstatus_ = (mstatus_ & ~0x88) | (mstatus_mie << 7);
    pc_ = (mtvec_ & ~0x3);
}

void Emulator::execute_instruction(uint32_t instr, TraceRecord& rec) {
    rec.pc = pc_;
    rec.raw_instr = instr;
    rec.cycle = cycles_;
    rec.retired_instrs = instret_;
    rec.disasm = Disassembler::disassemble(pc_, instr);

    uint32_t opcode = instr & 0x7F;
    uint32_t rd     = (instr >> 7) & 0x1F;
    uint32_t funct3 = (instr >> 12) & 0x07;
    uint32_t rs1    = (instr >> 15) & 0x1F;
    uint32_t rs2    = (instr >> 20) & 0x1F;
    uint32_t funct7 = (instr >> 25) & 0x7F;

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

    uint32_t next_pc = pc_ + 4;

    switch (opcode) {
        case 0x37: // LUI
            if (rd != 0) {
                regs_[rd] = imm_u;
                rec.has_rd = true;
                rec.rd_num = rd;
                rec.rd_val = imm_u;
            }
            break;

        case 0x17: // AUIPC
            if (rd != 0) {
                regs_[rd] = pc_ + imm_u;
                rec.has_rd = true;
                rec.rd_num = rd;
                rec.rd_val = regs_[rd];
            }
            break;

        case 0x6F: // JAL
            if (rd != 0) {
                regs_[rd] = next_pc;
                rec.has_rd = true;
                rec.rd_num = rd;
                rec.rd_val = next_pc;
            }
            next_pc = pc_ + imm_j;
            rec.is_branch = true;
            rec.branch_taken = true;
            rec.target_pc = next_pc;
            break;

        case 0x67: // JALR
            {
                uint32_t target = (regs_[rs1] + imm_i) & ~1U;
                if (rd != 0) {
                    regs_[rd] = next_pc;
                    rec.has_rd = true;
                    rec.rd_num = rd;
                    rec.rd_val = next_pc;
                }
                next_pc = target;
                rec.is_branch = true;
                rec.branch_taken = true;
                rec.target_pc = next_pc;
            }
            break;

        case 0x63: // Branches
            {
                branch_count_++;
                rec.is_branch = true;
                bool taken = false;
                switch (funct3) {
                    case 0x0: taken = (regs_[rs1] == regs_[rs2]); break; // BEQ
                    case 0x1: taken = (regs_[rs1] != regs_[rs2]); break; // BNE
                    case 0x4: taken = (static_cast<int32_t>(regs_[rs1]) < static_cast<int32_t>(regs_[rs2])); break; // BLT
                    case 0x5: taken = (static_cast<int32_t>(regs_[rs1]) >= static_cast<int32_t>(regs_[rs2])); break; // BGE
                    case 0x6: taken = (regs_[rs1] < regs_[rs2]); break; // BLTU
                    case 0x7: taken = (regs_[rs1] >= regs_[rs2]); break; // BGEU
                    default: break;
                }
                rec.branch_taken = taken;
                if (taken) {
                    next_pc = pc_ + imm_b;
                    rec.target_pc = next_pc;
                }
            }
            break;

        case 0x03: // Loads
            {
                load_count_++;
                rec.is_load = true;
                uint32_t addr = regs_[rs1] + imm_i;
                rec.mem_addr = addr;
                uint32_t data = 0;
                switch (funct3) {
                    case 0x0: // LB
                        data = static_cast<int32_t>(static_cast<int8_t>(read_u8(addr)));
                        rec.mem_bytes = 1;
                        break;
                    case 0x1: // LH
                        data = static_cast<int32_t>(static_cast<int16_t>(read_u16(addr)));
                        rec.mem_bytes = 2;
                        break;
                    case 0x2: // LW
                        data = read_u32(addr);
                        rec.mem_bytes = 4;
                        break;
                    case 0x4: // LBU
                        data = read_u8(addr);
                        rec.mem_bytes = 1;
                        break;
                    case 0x5: // LHU
                        data = read_u16(addr);
                        rec.mem_bytes = 2;
                        break;
                    default: break;
                }
                rec.mem_data = data;
                if (rd != 0) {
                    regs_[rd] = data;
                    rec.has_rd = true;
                    rec.rd_num = rd;
                    rec.rd_val = data;
                }
            }
            break;

        case 0x23: // Stores
            {
                store_count_++;
                rec.is_store = true;
                uint32_t addr = regs_[rs1] + imm_s;
                rec.mem_addr = addr;
                rec.mem_data = regs_[rs2];
                switch (funct3) {
                    case 0x0: // SB
                        write_u8(addr, static_cast<uint8_t>(regs_[rs2] & 0xFF));
                        rec.mem_bytes = 1;
                        break;
                    case 0x1: // SH
                        write_u16(addr, static_cast<uint16_t>(regs_[rs2] & 0xFFFF));
                        rec.mem_bytes = 2;
                        break;
                    case 0x2: // SW
                        write_u32(addr, regs_[rs2]);
                        rec.mem_bytes = 4;
                        break;
                    default: break;
                }
            }
            break;

        case 0x13: // ALU Immediate
            {
                uint32_t res = 0;
                uint32_t shamt = imm_i & 0x1F;
                switch (funct3) {
                    case 0x0: res = regs_[rs1] + imm_i; break; // ADDI
                    case 0x1: res = regs_[rs1] << shamt; break; // SLLI
                    case 0x2: res = (static_cast<int32_t>(regs_[rs1]) < imm_i) ? 1 : 0; break; // SLTI
                    case 0x3: res = (regs_[rs1] < static_cast<uint32_t>(imm_i)) ? 1 : 0; break; // SLTIU
                    case 0x4: res = regs_[rs1] ^ imm_i; break; // XORI
                    case 0x5:
                        if ((imm_i >> 5) & 0x20) {
                            res = static_cast<int32_t>(regs_[rs1]) >> shamt; // SRAI
                        } else {
                            res = regs_[rs1] >> shamt; // SRLI
                        }
                        break;
                    case 0x6: res = regs_[rs1] | imm_i; break; // ORI
                    case 0x7: res = regs_[rs1] & imm_i; break; // ANDI
                    default: break;
                }
                if (rd != 0) {
                    regs_[rd] = res;
                    rec.has_rd = true;
                    rec.rd_num = rd;
                    rec.rd_val = res;
                }
            }
            break;

        case 0x33: // ALU Register & M-Extension
            {
                uint32_t res = 0;
                if (funct7 == 0x01) { // M Extension
                    switch (funct3) {
                        case 0x0: // MUL
                            res = static_cast<uint32_t>(static_cast<int32_t>(regs_[rs1]) * static_cast<int32_t>(regs_[rs2]));
                            break;
                        case 0x1: // MULH
                            {
                                int64_t prod = static_cast<int64_t>(static_cast<int32_t>(regs_[rs1])) *
                                               static_cast<int64_t>(static_cast<int32_t>(regs_[rs2]));
                                res = static_cast<uint32_t>(prod >> 32);
                            }
                            break;
                        case 0x2: // MULHSU
                            {
                                int64_t prod = static_cast<int64_t>(static_cast<int32_t>(regs_[rs1])) *
                                               static_cast<uint64_t>(regs_[rs2]);
                                res = static_cast<uint32_t>(prod >> 32);
                            }
                            break;
                        case 0x3: // MULHU
                            {
                                uint64_t prod = static_cast<uint64_t>(regs_[rs1]) * static_cast<uint64_t>(regs_[rs2]);
                                res = static_cast<uint32_t>(prod >> 32);
                            }
                            break;
                        case 0x4: // DIV
                            if (regs_[rs2] == 0) {
                                res = 0xFFFFFFFF;
                            } else if (static_cast<int32_t>(regs_[rs1]) == INT32_MIN && static_cast<int32_t>(regs_[rs2]) == -1) {
                                res = INT32_MIN;
                            } else {
                                res = static_cast<uint32_t>(static_cast<int32_t>(regs_[rs1]) / static_cast<int32_t>(regs_[rs2]));
                            }
                            break;
                        case 0x5: // DIVU
                            if (regs_[rs2] == 0) {
                                res = 0xFFFFFFFF;
                            } else {
                                res = regs_[rs1] / regs_[rs2];
                            }
                            break;
                        case 0x6: // REM
                            if (regs_[rs2] == 0) {
                                res = regs_[rs1];
                            } else if (static_cast<int32_t>(regs_[rs1]) == INT32_MIN && static_cast<int32_t>(regs_[rs2]) == -1) {
                                res = 0;
                            } else {
                                res = static_cast<uint32_t>(static_cast<int32_t>(regs_[rs1]) % static_cast<int32_t>(regs_[rs2]));
                            }
                            break;
                        case 0x7: // REMU
                            if (regs_[rs2] == 0) {
                                res = regs_[rs1];
                            } else {
                                res = regs_[rs1] % regs_[rs2];
                            }
                            break;
                        default: break;
                    }
                } else { // Standard Base Integer ALU
                    uint32_t shamt = regs_[rs2] & 0x1F;
                    switch (funct3) {
                        case 0x0:
                            if (funct7 == 0x20) {
                                res = regs_[rs1] - regs_[rs2]; // SUB
                            } else {
                                res = regs_[rs1] + regs_[rs2]; // ADD
                            }
                            break;
                        case 0x1: res = regs_[rs1] << shamt; break; // SLL
                        case 0x2: res = (static_cast<int32_t>(regs_[rs1]) < static_cast<int32_t>(regs_[rs2])) ? 1 : 0; break; // SLT
                        case 0x3: res = (regs_[rs1] < regs_[rs2]) ? 1 : 0; break; // SLTU
                        case 0x4: res = regs_[rs1] ^ regs_[rs2]; break; // XOR
                        case 0x5:
                            if (funct7 == 0x20) {
                                res = static_cast<int32_t>(regs_[rs1]) >> shamt; // SRA
                            } else {
                                res = regs_[rs1] >> shamt; // SRL
                            }
                            break;
                        case 0x6: res = regs_[rs1] | regs_[rs2]; break; // OR
                        case 0x7: res = regs_[rs1] & regs_[rs2]; break; // AND
                        default: break;
                    }
                }
                if (rd != 0) {
                    regs_[rd] = res;
                    rec.has_rd = true;
                    rec.rd_num = rd;
                    rec.rd_val = res;
                }
            }
            break;

        case 0x07: // FLW
            {
                uint32_t addr = regs_[rs1] + imm_i;
                uint32_t val = read_u32(addr);
                fpregs_[rd] = val;
                rec.has_rd = true;
                rec.rd_num = rd;
                rec.rd_val = val;
                rec.is_fp = true;
            }
            break;

        case 0x27: // FSW
            {
                uint32_t addr = regs_[rs1] + imm_s;
                write_u32(addr, fpregs_[rs2]);
                rec.is_store = true;
                rec.mem_addr = addr;
                rec.mem_data = fpregs_[rs2];
                rec.mem_bytes = 4;
            }
            break;

        case 0x53: // FPU Operations
            {
                float f1 = std::bit_cast<float>(fpregs_[rs1]);
                float f2 = std::bit_cast<float>(fpregs_[rs2]);
                float fres = 0.0f;
                uint32_t ires = 0;
                bool dest_is_fp = true;

                switch (funct7) {
                    case 0x00: fres = f1 + f2; break; // FADD.S
                    case 0x04: fres = f1 - f2; break; // FSUB.S
                    case 0x08: fres = f1 * f2; break; // FMUL.S
                    case 0x0C: fres = f1 / f2; break; // FDIV.S
                    case 0x2C: fres = std::sqrt(f1); break; // FSQRT.S
                    case 0x14: // FMIN / FMAX
                        fres = (funct3 == 0) ? std::min(f1, f2) : std::max(f1, f2);
                        break;
                    case 0x60: // FCVT.W.S
                        dest_is_fp = false;
                        ires = (rs2 == 0) ? static_cast<uint32_t>(static_cast<int32_t>(f1))
                                          : static_cast<uint32_t>(f1);
                        break;
                    case 0x70: // FMV.X.W
                        dest_is_fp = false;
                        ires = fpregs_[rs1];
                        break;
                    case 0x50: // FEQ / FLT / FLE
                        dest_is_fp = false;
                        if (funct3 == 0) ires = (f1 <= f2) ? 1 : 0;
                        else if (funct3 == 1) ires = (f1 < f2) ? 1 : 0;
                        else if (funct3 == 2) ires = (f1 == f2) ? 1 : 0;
                        break;
                    case 0x68: // FCVT.S.W
                        fres = (rs2 == 0) ? static_cast<float>(static_cast<int32_t>(regs_[rs1]))
                                          : static_cast<float>(regs_[rs1]);
                        break;
                    case 0x78: // FMV.W.X
                        fres = std::bit_cast<float>(regs_[rs1]);
                        break;
                    default:
                        break;
                }

                if (dest_is_fp) {
                    fpregs_[rd] = std::bit_cast<uint32_t>(fres);
                    rec.has_rd = true;
                    rec.rd_num = rd;
                    rec.rd_val = fpregs_[rd];
                    rec.is_fp = true;
                } else if (rd != 0) {
                    regs_[rd] = ires;
                    rec.has_rd = true;
                    rec.rd_num = rd;
                    rec.rd_val = ires;
                }
            }
            break;

        case 0x73: // System / CSR
            if (funct3 == 0) {
                if (imm_i == 0x000) {
                    // ECALL
                    rec.is_trap = true;
                    rec.trap_cause = Cause::ECALL_M_MODE;
                    handle_trap(Cause::ECALL_M_MODE, 0);
                    return;
                } else if (imm_i == 0x302) {
                    // MRET
                    pc_ = mepc_;
                    return;
                }
            } else {
                // CSR Read/Write
                uint32_t csr_addr = (instr >> 20) & 0xFFF;
                uint32_t csr_val = 0;
                switch (csr_addr) {
                    case CSR::MSTATUS: csr_val = mstatus_; break;
                    case CSR::MISA:    csr_val = misa_; break;
                    case CSR::MIE:     csr_val = mie_; break;
                    case CSR::MTVEC:   csr_val = mtvec_; break;
                    case CSR::MEPC:    csr_val = mepc_; break;
                    case CSR::MCAUSE:  csr_val = mcause_; break;
                    case CSR::MTVAL:   csr_val = mtval_; break;
                    case CSR::MIP:     csr_val = mip_; break;
                    case CSR::MCYCLE:  csr_val = static_cast<uint32_t>(cycles_); break;
                    case CSR::MINSTRET: csr_val = static_cast<uint32_t>(instret_); break;
                    default: break;
                }

                uint32_t wdata = (funct3 & 0x4) ? rs1 : regs_[rs1];
                uint32_t new_val = csr_val;
                if ((funct3 & 0x3) == 1) new_val = wdata; // CSRRW
                else if ((funct3 & 0x3) == 2) new_val |= wdata; // CSRRS
                else if ((funct3 & 0x3) == 3) new_val &= ~wdata; // CSRRC

                switch (csr_addr) {
                    case CSR::MSTATUS: mstatus_ = new_val; break;
                    case CSR::MIE:     mie_ = new_val; break;
                    case CSR::MTVEC:   mtvec_ = new_val; break;
                    case CSR::MEPC:    mepc_ = new_val; break;
                    case CSR::MCAUSE:  mcause_ = new_val; break;
                    case CSR::MTVAL:   mtval_ = new_val; break;
                    default: break;
                }

                if (rd != 0) {
                    regs_[rd] = csr_val;
                    rec.has_rd = true;
                    rec.rd_num = rd;
                    rec.rd_val = csr_val;
                }
            }
            break;

        case 0x0F: // FENCE
            break;

        default:
            std::cerr << "[Talos Golden Emu] Warning: Unrecognized instruction 0x"
                      << std::hex << instr << " at PC 0x" << pc_ << std::dec << "\n";
            break;
    }

    regs_[0] = 0; // Hardwired zero
    pc_ = next_pc;
}

ExitStatus Emulator::step() {
    if (pc_ < RAM_BASE && pc_ >= ROM_BASE + ROM_SIZE) {
        return ExitStatus::FAILURE;
    }

    uint32_t instr = read_u32(pc_);
    TraceRecord rec;
    execute_instruction(instr, rec);

    instret_++;
    // Advance cycle: simulates dual-issue execution
    if ((instret_ % 2) == 0) {
        cycles_++;
        update_timers();
    }

    if (trace_enabled_) {
        std::ostream& os = trace_file_.is_open() ? trace_file_ : std::cout;
        os << "[" << std::setw(8) << rec.cycle << "] "
           << "PC=0x" << std::hex << std::setw(8) << std::setfill('0') << rec.pc << " "
           << "INSTR=0x" << std::setw(8) << rec.raw_instr << " "
           << std::setfill(' ') << std::left << std::setw(32) << rec.disasm;

        if (rec.has_rd) {
            os << " " << (rec.is_fp ? Disassembler::fp_reg_name(rec.rd_num) : Disassembler::reg_name(rec.rd_num))
               << "=0x" << std::hex << rec.rd_val;
        }
        if (rec.is_load || rec.is_store) {
            os << " [MEM 0x" << std::hex << rec.mem_addr << "=" << rec.mem_data << "]";
        }
        os << std::dec << "\n";
    }

    // Check TOHOST termination
    if (tohost_val_ != 0) {
        if (tohost_val_ == 1) {
            return ExitStatus::SUCCESS;
        }
        return ExitStatus::FAILURE;
    }

    if (cycles_ >= max_cycles_) {
        return ExitStatus::TIMEOUT;
    }

    return ExitStatus::RUNNING;
}

ExitStatus Emulator::run() {
    ExitStatus status = ExitStatus::RUNNING;
    while (status == ExitStatus::RUNNING) {
        status = step();
    }
    return status;
}

void Emulator::dump_registers(std::ostream& os) const {
    os << "\n================ Architectural Register State ================\n";
    for (size_t i = 0; i < 32; i += 4) {
        for (size_t j = 0; j < 4; ++j) {
            size_t r = i + j;
            os << std::setw(5) << std::right << Disassembler::reg_name(r) << ":"
               << " 0x" << std::hex << std::setw(8) << std::setfill('0') << regs_[r] << "  ";
        }
        os << "\n";
    }
    os << "PC:    0x" << std::hex << std::setw(8) << std::setfill('0') << pc_ << "\n";
    os << "Cycles: " << std::dec << cycles_ << " | Retired: " << instret_ << "\n";
    os << "==============================================================\n";
}

void Emulator::print_statistics(std::ostream& os) const {
    double ipc = cycles_ > 0 ? static_cast<double>(instret_) / static_cast<double>(cycles_) : 0.0;
    os << "\n---------------- Simulation Performance Metrics ----------------\n";
    os << "Total Cycles:        " << cycles_ << "\n";
    os << "Retired Instructions:" << instret_ << "\n";
    os << "Sustained IPC:       " << std::fixed << std::setprecision(3) << ipc << "\n";
    os << "Total Branches:      " << branch_count_ << "\n";
    os << "Total Loads:         " << load_count_ << "\n";
    os << "Total Stores:        " << store_count_ << "\n";
    os << "----------------------------------------------------------------\n";
}

} // namespace talos

int main(int argc, char** argv) {
    std::string elf_path;
    std::string hex_path;
    std::string bin_path;
    std::string trace_file;
    bool enable_trace = false;
    bool dump_regs = false;
    bool verbose = false;
    uint64_t max_cycles = 5000000;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--elf" && i + 1 < argc) {
            elf_path = argv[++i];
        } else if (arg == "--hex" && i + 1 < argc) {
            hex_path = argv[++i];
        } else if (arg == "--bin" && i + 1 < argc) {
            bin_path = argv[++i];
        } else if (arg == "--trace") {
            enable_trace = true;
        } else if (arg == "--trace-file" && i + 1 < argc) {
            enable_trace = true;
            trace_file = argv[++i];
        } else if (arg == "--max-cycles" && i + 1 < argc) {
            max_cycles = std::stoull(argv[++i]);
        } else if (arg == "--dump-regs") {
            dump_regs = true;
        } else if (arg == "--verbose") {
            verbose = true;
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: talos_emu [options]\n"
                      << "  --elf <path>         Load ELF binary\n"
                      << "  --hex <path>         Load HEX memory image\n"
                      << "  --bin <path>         Load raw binary image\n"
                      << "  --trace              Output execution trace\n"
                      << "  --trace-file <path>  Write trace to file\n"
                      << "  --max-cycles <N>     Maximum execution cycles (default: 5,000,000)\n"
                      << "  --dump-regs          Print registers on exit\n"
                      << "  --verbose            Enable verbose output\n";
            return 0;
        }
    }

    talos::Emulator emu;
    emu.set_max_cycles(max_cycles);
    emu.set_verbose(verbose);
    if (enable_trace) {
        emu.enable_tracing(true, trace_file);
    }

    if (!elf_path.empty()) {
        if (!emu.load_elf(elf_path)) {
            std::cerr << "[Talos Emu] Error loading ELF: " << elf_path << "\n";
            return 1;
        }
    } else if (!hex_path.empty()) {
        if (!emu.load_hex(hex_path)) {
            std::cerr << "[Talos Emu] Error loading HEX: " << hex_path << "\n";
            return 1;
        }
    } else if (!bin_path.empty()) {
        if (!emu.load_bin(bin_path)) {
            std::cerr << "[Talos Emu] Error loading binary: " << bin_path << "\n";
            return 1;
        }
    } else {
        std::cout << "[Talos Emu] No input binary specified. Golden simulator ready.\n";
        return 0;
    }

    talos::ExitStatus status = emu.run();

    if (dump_regs) {
        emu.dump_registers(std::cout);
    }
    emu.print_statistics(std::cout);

    if (status == talos::ExitStatus::SUCCESS) {
        std::cout << "[Talos Emu] Simulation PASSED.\n";
        return 0;
    } else if (status == talos::ExitStatus::TIMEOUT) {
        std::cerr << "[Talos Emu] Simulation TIMED OUT.\n";
        return 2;
    } else {
        std::cerr << "[Talos Emu] Simulation FAILED (tohost=0x"
                  << std::hex << emu.get_tohost_val() << std::dec << ").\n";
        return 1;
    }
}
