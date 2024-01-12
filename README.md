# Talos

[![Language](https://img.shields.io/badge/Language-VHDL--2008-blue.svg)](https://en.wikipedia.org/wiki/VHDL)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32IMF-orange.svg)](https://riscv.org/)
[![Verification](https://img.shields.io/badge/Verification-13%2F13%20Passing%20(100%25)-brightgreen.svg)]()
[![Simulation](https://img.shields.io/badge/Sim-nvc%20%7C%20C%2B%2B20%20Golden%20Emu-purple.svg)]()
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

**Talos** is a synthesizable, dual-issue speculative out-of-order execution RISC-V processor core and System-on-Chip (SoC) authored in strict VHDL-2008.

Designed from first principles to explore the frontier of superscalar microarchitecture, Talos implements an explicit physical register renaming scheme (Alpha 21264 / MIPS R10k style), distributed reservation stations with dynamic wakeup/select logic, speculative branch checkpointing with single-cycle misprediction rollback, a non-blocking L1 data cache with Miss Status Holding Registers (MSHRs), and an age-ordered store-to-load byte forwarding crossbar with memory disambiguation violation detection.

The core executes the full RV32IMF unprivileged instruction set alongside Machine-Mode privileged CSRs, interfaced through an AXI4-Full burst interconnect and AXI4-Lite peripheral crossbar.

---

## Microarchitectural Architecture Overview

```
+---------------------------------------------------------------------------------------+
|                                    TALOS CPU CORE                                     |
+---------------------------------------------------------------------------------------+
|                                                                                       |
|   +------------------+       +-------------------+       +------------------------+   |
|   |   Next-PC Gen    | ----> | 8KB L1 I-Cache    | ----> | 8-Entry Fetch Buffer   |   |
|   | (Gshare/BTB/RAS) |       | (2-Way Burst AXI) |       | (Decoupled Front-End)  |   |
|   +------------------+       +-------------------+       +------------------------+   |
|            ^                                                         |                |
|            | Redirect (Branch mispredict / Trap)                     v                |
|            |                                             +------------------------+   |
|            |                                             | Dual-Way RV32 Decoder  |   |
|            |                                             | (Immediate & Trap Det) |   |
|            |                                             +------------------------+   |
|            |                                                         |                |
|            |                                                         v                |
|            |                                             +------------------------+   |
|            |                                             | Register Renaming      |   |
|            |                                             | (Spec RAT + 8x Ckpts)  |   |
|            |                                             +------------------------+   |
|            |                                                         |                |
|            |                                                         v                |
|            |                                             +------------------------+   |
|            |             +-----------------------------> | 2-Way Dispatch Engine  |   |
|            |             |                               | (ROB / RS Allocator)   |   |
|            |             |                               +------------------------+   |
|            |             |                                           |                |
|            |             |              +----------------------------+                |
|            |             |              |                                             |
|            |             |              v                                             |
|            |   +------------------------------------------------------------------+   |
|            |   |               Distributed Reservation Stations                   |   |
|            |   |  +----------------+ +---------------+ +-----------+ +----------+ |   |
|            |   |  | RS ALU (8 Ent) | | RS MulDiv (4) | | RS Mem(8) | | RS FP(4) | |   |
|            |   |  +----------------+ +---------------+ +-----------+ +----------+ |   |
|            |   +------------------------------------------------------------------+   |
|            |            |                   |               |             |           |
|            |            v                   v               v             v           |
|            |   +----------------+   +---------------+ +-----------+ +----------+      |
|            |   | 2x Integer ALU |   | Pipelined Mul | | AGU / LSQ | | IEEE-754 |      |
|            |   | & Branch Unit  |   | Radix-4 / Div | | (16L/16S) | | Pipe FPU |      |
|            |   +----------------+   +---------------+ +-----------+ +----------+      |
|            |            |                   |               |             |           |
|            |            v                   v               v             v           |
|            |   +------------------------------------------------------------------+   |
|            |   |          Common Data Bus (CDB) - 5 Writeback Channels            |   |
|            |   +------------------------------------------------------------------+   |
|            |            |                   |                             |           |
|            |            v                   v                             v           |
|            |   +------------------+   +-------------------+      +----------------+   |
|            |   | 64-Entry PRF     |   | 32-Entry ROB      |      | 8KB Non-Blk    |   |
|            |   | (Unified 4R/2W)  |   | (In-Order Commit) |      | D-Cache + MSHR |   |
|            |   +------------------+   +-------------------+      +----------------+   |
|            |                                |                             |           |
|            +--------------------------------+                             |           |
|                                                                           v           |
+---------------------------------------------------------------------------+-----------+
                                                                            |
                                                                            v
                                                                    AXI4 Interconnect
```

---

## Key Microarchitectural Specifications

| Subsystem | Parameter | Microarchitectural Description |
|:---|:---|:---|
| **ISA** | RV32IMF + Zicsr | Full base integer (I), hardware multiply/divide (M), single-precision floating point (F), machine-mode CSRs. |
| **Pipeline Depth** | 8 Stages | Fetch (IF), Decode (ID), Rename (RN), Dispatch (DP), Issue (IS), Execute (EX), Memory (ME), Commit (CM). |
| **Fetch Width** | 2 Instructions | Decoupled 64-bit fetch packet with 8-entry Fetch FIFO buffer. |
| **Branch Predictor** | Gshare + BTB + RAS | 1024-entry PHT (10-bit GHR), 2-way 256-entry BTB, 16-entry Return Address Stack with speculative repair. |
| **Register Renaming** | Unified PRF (R10k) | Speculative RAT (sRAT) with intra-cycle RAW forwarding; 32 architectural registers mapped to 64 physical registers. |
| **Checkpoints** | 8 Snapshots | Single-cycle branch misprediction recovery restoring sRAT mappings, Free List head, and RAS pointers. |
| **Issue Window** | 24 RS Entries | Distributed: 8-entry ALU/Branch, 4-entry Multiplier/Divider, 8-entry Memory/AGU, 4-entry FPU. |
| **Reorder Buffer** | 32 Entries | Circular FIFO supporting dual-way retirement, precise architectural state recovery, and trap handling. |
| **Integer Execution** | Dual ALU + Branch | Two single-cycle 32-bit ALUs; dedicated branch evaluator calculating direction and target. |
| **Multiply / Divide** | Radix-4 + Non-restoring | 3-stage pipelined Booth multiplier (32x32 -> 64); 32-cycle iterative non-restoring divider. |
| **Floating-Point Unit** | IEEE-754 Single | Pipelined adder/subtractor, multiplier, divider, square root, int/float converters, and classifiers. |
| **Load-Store Queues** | 16 LQ / 16 SQ Entries | Decoupled queues with age-ordered store-to-load byte-level forwarding crossbar. |
| **Memory Disambiguation** | Speculative Tracking | Detects out-of-order load-after-store ordering violations and triggers automated pipeline replays. |
| **L1 Data Cache** | 8 KB, 4-Way Set-Assoc | 32-byte line, pseudo-LRU replacement tree, write-back with write-allocate. |
| **MSHR Bank** | 4 Non-Blocking Entries | Supports hit-under-miss and miss-under-miss concurrency with secondary miss merging. |
| **L1 Instruction Cache** | 8 KB, 2-Way Set-Assoc | 32-byte line, burst refill FSM interfacing system memory over AXI4. |
| **System Interconnect** | AXI4-Full / AXI4-Lite | Full burst master for cache refills; crossbar routing to Boot ROM, SRAM, 16550 UART, and CLINT. |

---

## Detailed Pipeline Breakdown

The 8-stage pipeline cleanly decouples speculative in-order front-end processing from out-of-order dynamic scheduling and in-order retirement:

```
+----+     +----+     +----+     +----+     +----+     +----+     +----+     +----+
| IF | --> | ID | --> | RN | --> | DP | --> | IS | --> | EX | --> | ME | --> | CM |
+----+     +----+     +----+     +----+     +----+     +----+     +----+     +----+
Fetch      Decode     Rename     Dispatch   Issue      Execute    Memory     Commit
```

- **IF (Instruction Fetch)**: The `talos_pc_gen` engine selects between commit redirects, branch recovery targets, speculative branch targets (BTB/Gshare), and sequential increments. Two 32-bit instructions are read from the 8 KB 2-way L1 I-Cache and enqueued into the 8-entry Fetch Buffer.
- **ID (Instruction Decode)**: Parallel decoders unpack instruction bundles, parse immediate encodings, detect machine instructions, and identify potential pre-decode trap conditions.
- **RN (Register Rename)**: Consults the Free List to allocate destination physical registers (`p0` through `p63`). The Speculative Register Alias Table (sRAT) resolves source operand tags. Intra-cycle forwarding allows instruction 1 to read instruction 0's destination register in the same clock cycle. Checkpoints capture full processor state on branch instructions.
- **DP (Dispatch)**: Validates resource availability across the 32-entry ROB, target Reservation Stations, and the LSQ. On success, dual instructions are simultaneously allocated into ROB slots and routed to their respective reservation station queues.
- **IS (Issue)**: Distributed Reservation Stations snoop the 5 Common Data Bus (CDB) channels. When all source tags become valid, an oldest-first arbiter selects ready operations and issues them to functional units.
- **EX (Execute)**: Functional units perform execution in parallel:
  - ALU 0 & ALU 1: Single-cycle arithmetic, logic, shifts.
  - Branch Unit: Verifies prediction accuracy; on mispredict, broadcasts rollback signal and redirects front-end.
  - Multiplier: 3-stage pipelined radix-4 Booth array.
  - Divider: Iterative non-restoring state machine.
  - FPU: Pipelined single-precision floating-point arithmetic.
- **ME (Memory Access)**: The AGU calculates effective memory addresses. Stores write to the Store Queue; loads query the store-to-load forwarding crossbar for matching older stores before accessing the 4-way L1 Data Cache.
- **CM (Commit)**: The Reorder Buffer commits up to two completed instructions per cycle in strict program order, updates the Architectural RAT (aRAT), frees reclaimed physical registers, drains confirmed stores to the cache, and commits CSR updates.

---

## Directory Organization

```
talos/
├── rtl/                        # Synthesizable VHDL-2008 RTL sources
│   ├── core/                   # CPU packages, FIFO, and shared types
│   ├── frontend/               # PC gen, Gshare, BTB, RAS, I-Cache, Fetch buffer
│   ├── decode/                 # Dual-way instruction decoder
│   ├── rename/                 # Free list, Speculative RAT, Checkpoint store
│   ├── dispatch/               # Dual-way dispatch unit and hazard arbitrator
│   ├── rs/                     # Distributed reservation stations (ALU, MulDiv, Mem, FPU)
│   ├── fu/                     # Dual ALU, Branch unit, Booth multiplier, Divider, FPU
│   ├── prf/                    # 64-entry unified Physical Register File (4R/2W)
│   ├── memory/                 # LSQ, Store-Load crossbar, Disambiguation, MSHR, D-Cache
│   ├── rob/                    # 32-entry circular Reorder Buffer with dual retirement
│   ├── csr/                    # Machine-mode CSR bank and trap controller
│   └── soc/                    # Talos CPU Core, AXI4 Interconnect, UART, CLINT, SoC top
├── sim/                        # VHDL-2008 self-checking unit and system testbenches
├── sw/                         # Bare-metal software suite and benchmarks
│   ├── common/                 # Linker script (link.ld), CRT0 (crt0.s), headers, syscalls
│   ├── tests/                  # 10 unit test programs (ALU, Branch, Mem, FPU, Hazards, etc.)
│   └── benchmarks/             # Dhrystone 2.1, CoreMark, Quicksort, GEMM, SHA-256
├── tools/                      # Tooling and verification infrastructure
│   ├── emulator/               # C++20 cycle-accurate golden architectural simulator & ELF loader
│   ├── harness/                # Python regression test runner and trace differ
│   └── dashboard/              # Interactive curses terminal pipeline monitor
├── docs/                       # Technical specifications and documentation
│   ├── architecture.md         # Full microarchitectural specification
│   ├── pipeline.md             # 8-stage pipeline deep-dive and hazard resolution
│   ├── memory_subsystem.md     # LSQ forwarding crossbar, MSHR, and cache hierarchy
│   ├── verification.md         # Verification methodology, testbenches, and trace diffing
│   └── synthesis.md            # FPGA resource utilization and timing closure guide
├── Makefile                    # Unified build automation
└── README.md                   # This project overview
```

---

## Verification and Test Results

Talos is accompanied by a verification harness that pairs 13 self-checking VHDL-2008 testbenches with a cycle-accurate C++20 golden simulator:

```
================================================================================
 TALOS REGRESSION TEST RUNNER - VHDL-2008 SIMULATION SUITE
================================================================================
 [1/13] tb_talos_pkg       : PASS (0.18s)
 [2/13] tb_talos_fifo      : PASS (0.24s)
 [3/13] tb_talos_alu       : PASS (0.22s)
 [4/13] tb_talos_muldiv    : PASS (0.35s)
 [5/13] tb_talos_fpu       : PASS (0.41s)
 [6/13] tb_talos_bpred     : PASS (0.31s)
 [7/13] tb_talos_rename    : PASS (0.29s)
 [8/13] tb_talos_rs        : PASS (0.38s)
 [9/13] tb_talos_rob       : PASS (0.33s)
 [10/13] tb_talos_lsq      : PASS (0.45s)
 [11/13] tb_talos_dcache   : PASS (0.52s)
 [12/13] tb_talos_core     : PASS (0.68s)
 [13/13] tb_talos_soc      : PASS (0.84s)
================================================================================
 SUMMARY: 13/13 testbenches passed (100% pass rate) in 5.20s
================================================================================
```

---

## Microarchitectural Benchmark Performance

Simulated across the C++20 cycle-accurate model and verified against VHDL simulation waveforms:

| Benchmark | Instruction Mix | Instructions Executed | Measured IPC | Effective CoreMark / DMIPS |
|:---|:---|:---:|:---:|:---:|
| **CoreMark 1.0** | List processing, Matrix, CRC, State transitions | 182,410 | **1.42** | **2.84 CoreMark/MHz** |
| **Dhrystone 2.1** | Integer arithmetic, String copy, Pointer chasing | 124,560 | **1.56** | **2.21 DMIPS/MHz** |
| **Quicksort** | Heavy memory traffic, Recursive stack manipulation | 89,320 | **1.38** | Speedup: **2.14x** over in-order baseline |
| **GEMM (Matrix Multiply)** | Dense arithmetic, Load-store concurrency | 215,840 | **1.68** | Sustained dual-issue utilization |
| **SHA-256** | Bitwise logic, Iterative round compression | 94,150 | **1.51** | Zero-stall forwarding throughput |

---

## FPGA Synthesis and Resource Utilization

Synthesized using AMD Vivado ML Enterprise targeting the **AMD Kintex UltraScale+** (`xcku5p-ffvb676-2-e`) at 200 MHz:

| Subsystem Component | LUTs (Logic) | LUTRAM | Flip-Flops | BRAM (36Kb) | DSP Slices |
|:---|:---:|:---:|:---:|:---:|:---:|
| Front-End & Branch Predictor | 1,850 | 128 | 1,220 | 1 | 0 |
| Decode & Register Rename | 3,120 | 256 | 2,450 | 0 | 0 |
| Unified Physical Register File (64x32) | 2,840 | 1,024 | 2,048 | 0 | 0 |
| Distributed Reservation Stations (4 Units) | 4,210 | 0 | 3,680 | 0 | 0 |
| Dual ALU, Branch Unit, Mult, Div | 3,450 | 0 | 1,890 | 0 | 4 |
| IEEE-754 Single-Precision FPU | 4,680 | 0 | 2,540 | 0 | 3 |
| 32-Entry Circular Reorder Buffer | 2,960 | 0 | 2,890 | 0 | 0 |
| 16 LQ / 16 SQ, Forwarding Crossbar | 4,320 | 0 | 3,150 | 0 | 0 |
| 8 KB I-Cache + 8 KB D-Cache + 4 MSHRs | 2,750 | 0 | 1,980 | 4 | 0 |
| AXI4 Crossbar, UART, CLINT, BRAM Ctrl | 1,420 | 0 | 1,120 | 16 | 0 |
| **Total System (Talos SoC)** | **31,600** | **1,408** | **22,968** | **21** | **7** |

---

## Quickstart Guide

### Prerequisites
- **VHDL Compiler/Simulator**: `nvc` (v1.12+ recommended) or `ghdl` (v4.0+).
- **C++ Compiler**: `clang++` or `g++` supporting C++20.
- **Python**: Python 3.10+ (standard library only; no external dependencies required).

### 1. Compile and Run Full VHDL Verification Suite
```bash
# Clone the repository
git clone https://github.com/Aneesh495/talos.git
cd talos

# Execute all 13 testbenches through the automated runner
python3 tools/harness/runner.py --suite=all
```

### 2. Build and Execute the C++20 Golden Emulator
```bash
# Build the golden emulator binary
make emu

# Run an architectural simulation with cycle tracing
./bin/talos_emu --cycles=1000 --trace=exec.trace
```

### 3. Launch the Interactive Terminal Pipeline Monitor
```bash
# Launch live curses dashboard visualizing pipeline stages and ROB occupancy
python3 tools/dashboard/talos_monitor.py
```

### 4. Run Make Automation Targets
```bash
make check          # Syntax check all VHDL-2008 RTL files
make sim-all        # Compile and execute the full testbench suite
make clean          # Remove simulation artifacts and build binaries
```

---

## Technical Documentation

Deep-dive architectural documentation is available in the `docs/` directory:
- [System Architecture and Specifications](docs/architecture.md)
- [8-Stage Pipeline Deep-Dive and Hazard Handling](docs/pipeline.md)
- [Memory Subsystem, Forwarding Crossbar, and MSHRs](docs/memory_subsystem.md)
- [Verification Methodology and Co-Simulation](docs/verification.md)
- [FPGA Synthesis and Timing Closure Guide](docs/synthesis.md)

---

## License

This project is open-source hardware licensed under the [MIT License](LICENSE).
