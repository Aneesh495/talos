// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Golden Emulator: High-Performance RV32IMF Disassembler Header
// Standard: C++20
// ==============================================================================

#pragma once

#include <cstdint>
#include <string>

namespace talos {

class Disassembler {
public:
    static std::string disassemble(uint32_t pc, uint32_t instr);
    static const char* reg_name(uint32_t r);
    static const char* fp_reg_name(uint32_t r);
    static const char* csr_name(uint32_t csr);
};

} // namespace talos
