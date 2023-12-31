// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Golden Emulator: Architectural Types and System Memory Map Definitions
// Standard: C++20
// ==============================================================================

#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <array>
#include <optional>

namespace talos {

// Architectural bit widths and limits
constexpr uint32_t XLEN = 32;
constexpr size_t NUM_INT_REGS = 32;
constexpr size_t NUM_FP_REGS = 32;

// Standard SoC Memory Map
constexpr uint32_t ROM_BASE   = 0x00010000;
constexpr uint32_t ROM_SIZE   = 0x00010000; // 64 KB Boot ROM

constexpr uint32_t CLINT_BASE = 0x02000000;
constexpr uint32_t CLINT_SIZE = 0x00010000; // 64 KB CLINT (Timer)

constexpr uint32_t UART_BASE  = 0x10000000;
constexpr uint32_t UART_SIZE  = 0x00001000; // 4 KB UART 16550

constexpr uint32_t RAM_BASE   = 0x80000000;
constexpr uint32_t RAM_SIZE   = 0x00400000; // 4 MB Emulation RAM

// TOHOST Communication (Standard RISC-V test signature)
constexpr uint32_t TOHOST_ADDR = 0x80001000;

// RISC-V Exception and Trap Causes
namespace Cause {
    constexpr uint32_t INSTR_ADDR_MISALIGN = 0;
    constexpr uint32_t INSTR_ACCESS_FAULT  = 1;
    constexpr uint32_t ILLEGAL_INSTR       = 2;
    constexpr uint32_t BREAKPOINT          = 3;
    constexpr uint32_t LOAD_ADDR_MISALIGN  = 4;
    constexpr uint32_t LOAD_ACCESS_FAULT   = 5;
    constexpr uint32_t STORE_ADDR_MISALIGN = 6;
    constexpr uint32_t STORE_ACCESS_FAULT  = 7;
    constexpr uint32_t ECALL_U_MODE        = 8;
    constexpr uint32_t ECALL_M_MODE        = 11;

    constexpr uint32_t INT_SOFTWARE        = 0x80000003;
    constexpr uint32_t INT_TIMER           = 0x80000007;
    constexpr uint32_t INT_EXTERNAL        = 0x8000000B;
}

// Privileged CSR Addresses
namespace CSR {
    constexpr uint32_t MSTATUS   = 0x300;
    constexpr uint32_t MISA      = 0x301;
    constexpr uint32_t MEDELEG   = 0x302;
    constexpr uint32_t MIDELEG   = 0x303;
    constexpr uint32_t MIE       = 0x304;
    constexpr uint32_t MTVEC     = 0x305;
    constexpr uint32_t MEPC      = 0x341;
    constexpr uint32_t MCAUSE    = 0x342;
    constexpr uint32_t MTVAL     = 0x343;
    constexpr uint32_t MIP       = 0x344;
    constexpr uint32_t MCYCLE    = 0xB00;
    constexpr uint32_t MINSTRET  = 0xB02;
    constexpr uint32_t MCYCLEH   = 0xB80;
    constexpr uint32_t MINSTRETH = 0xB82;
}

// Architectural Trace Record for Co-Simulation Diffing
struct TraceRecord {
    uint64_t cycle{0};
    uint64_t retired_instrs{0};
    uint32_t pc{0};
    uint32_t raw_instr{0};
    std::string disasm;
    
    // Register writeback
    bool     has_rd{false};
    uint32_t rd_num{0};
    uint32_t rd_val{0};
    bool     is_fp{false};

    // Memory access
    bool     is_load{false};
    bool     is_store{false};
    uint32_t mem_addr{0};
    uint32_t mem_data{0};
    uint8_t  mem_bytes{0};

    // Control flow
    bool     is_branch{false};
    bool     branch_taken{false};
    uint32_t target_pc{0};

    // Trap / Exception
    bool     is_trap{false};
    uint32_t trap_cause{0};
};

// Execution Status
enum class ExitStatus {
    RUNNING,
    SUCCESS,
    FAILURE,
    TIMEOUT,
    TRAP,
    HALT
};

} // namespace talos
