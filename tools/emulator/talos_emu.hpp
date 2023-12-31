// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Golden Emulator: Architectural Simulator Engine Header
// Standard: C++20
// ==============================================================================

#pragma once

#include "talos_types.hpp"
#include <string>
#include <vector>
#include <memory>
#include <fstream>
#include <iostream>

namespace talos {

class Emulator {
public:
    Emulator();
    ~Emulator() = default;

    // Configuration and Initialization
    void reset(uint32_t start_pc = 0x80000000);
    bool load_elf(const std::string& path);
    bool load_hex(const std::string& path);
    bool load_bin(const std::string& path, uint32_t offset = 0);

    void set_max_cycles(uint64_t max_c) { max_cycles_ = max_c; }
    void enable_tracing(bool enable, const std::string& trace_path = "");
    void set_tohost_addr(uint32_t addr) { tohost_addr_ = addr; }
    void set_verbose(bool v) { verbose_ = v; }

    // Execution Controls
    ExitStatus step();
    ExitStatus run();

    // Inspection and Diagnostics
    void dump_registers(std::ostream& os = std::cout) const;
    void print_statistics(std::ostream& os = std::cout) const;

    uint32_t get_reg(size_t r) const { return r < 32 ? regs_[r] : 0; }
    uint32_t get_pc() const { return pc_; }
    uint64_t get_cycles() const { return cycles_; }
    uint64_t get_instret() const { return instret_; }
    uint32_t get_tohost_val() const { return tohost_val_; }

    // Memory Access Interface
    uint8_t  read_u8(uint32_t addr);
    uint16_t read_u16(uint32_t addr);
    uint32_t read_u32(uint32_t addr);

    void write_u8(uint32_t addr, uint8_t val);
    void write_u16(uint32_t addr, uint16_t val);
    void write_u32(uint32_t addr, uint32_t val);

private:
    // Core Execution Helpers
    void execute_instruction(uint32_t instr, TraceRecord& rec);
    void handle_trap(uint32_t cause, uint32_t tval);
    void update_timers();

    // State Variables
    uint32_t pc_{0x80000000};
    std::array<uint32_t, 32> regs_{};
    std::array<uint32_t, 32> fpregs_{};
    
    // CSR Registers
    uint32_t mstatus_{0x1800}; // MPP = 3 (Machine Mode)
    uint32_t misa_{0x40101124};   // RV32IMF
    uint32_t mie_{0};
    uint32_t mtvec_{0};
    uint32_t mepc_{0};
    uint32_t mcause_{0};
    uint32_t mtval_{0};
    uint32_t mip_{0};
    uint32_t fcsr_{0};

    // CLINT Memory-Mapped Timers
    uint64_t mtime_{0};
    uint64_t mtimecmp_{UINT64_MAX};

    // System Memory Buffers
    std::vector<uint8_t> rom_;
    std::vector<uint8_t> ram_;

    // Emulation Metadata and Metrics
    uint64_t cycles_{0};
    uint64_t instret_{0};
    uint64_t max_cycles_{10000000};
    uint32_t tohost_addr_{TOHOST_ADDR};
    uint32_t tohost_val_{0};

    // Performance Metrics
    uint64_t branch_count_{0};
    uint64_t branch_mispred_{0};
    uint64_t load_count_{0};
    uint64_t store_count_{0};
    uint64_t fwd_count_{0};

    bool verbose_{false};
    bool trace_enabled_{false};
    std::ofstream trace_file_;
};

} // namespace talos
