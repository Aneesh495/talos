# Talos Verification Methodology and Test Framework

The verification environment for Talos employs a multi-tiered validation methodology designed to verify microarchitectural correctness across all out-of-order execution scenarios, pipeline hazards, memory disambiguation violations, branch mispredictions, and IEEE-754 corner cases.

---

## 1. Verification Strategy Overview

```
+-----------------------------------------------------------------------------+
|                            VERIFICATION SUITE                               |
+-----------------------------------------------------------------------------+
|                                                                             |
|   +--------------------------+       +----------------------------------+   |
|   | VHDL-2008 Testbenches    |       | C++20 Cycle-Accurate Golden Sim  |   |
|   | (13 Unit & System TBs)   |       | (Full RV32IMF Architectural Ref) |   |
|   +--------------------------+       +----------------------------------+   |
|                |                                      |                     |
|                | Simulation Waveforms & Traces        | Golden Cycle Trace  |
|                v                                      v                     |
|   +---------------------------------------------------------------------+   |
|   |                   Automated Trace Differ Engine                     |   |
|   |           (Register States, Memory Writes, CSR Updates)             |   |
|   +---------------------------------------------------------------------+   |
|                                     |                                       |
|                                     v                                       |
|   +---------------------------------------------------------------------+   |
|   |                 Automated Regression Test Runner                    |   |
|   |          (Pass/Fail Assertions, Latency, Throughput Metrics)        |   |
|   +---------------------------------------------------------------------+   |
|                                                                             |
+-----------------------------------------------------------------------------+
```

---

## 2. VHDL Unit and Integration Testbenches

The test suite in `sim/` contains 13 dedicated self-checking VHDL testbenches compiled and simulated with `nvc`:

| Testbench | Target Module | Scope of Verification |
|:---|:---|:---|
| `tb_talos_pkg.vhd` | `talos_pkg.vhd` | Type definitions, record pack/unpack, bitfield slicing, encoding constants. |
| `tb_talos_fifo.vhd` | `talos_fifo.vhd` | Dual-port FIFO, full/empty flag transitions, wrap-around pointers, simultaneous read/write. |
| `tb_talos_alu.vhd` | `talos_alu.vhd` | 32-bit arithmetic, logic, barrel shifters (SLL, SRL, SRA), SLT/SLTU comparisons. |
| `tb_talos_muldiv.vhd` | `talos_multiplier.vhd`, `talos_divider.vhd` | Radix-4 Booth pipeline, iterative non-restoring divider, divide-by-zero, signed/unsigned overflow. |
| `tb_talos_fpu.vhd` | `talos_fpu_top.vhd` | IEEE-754 single-precision addition, subtraction, multiplication, division, square root, conversions, subnormals, NaNs. |
| `tb_talos_bpred.vhd` | `talos_gshare.vhd`, `talos_btb.vhd`, `talos_ras.vhd` | PHT updates, 2-way BTB associative lookups, RAS push/pop/recovery on speculative branches. |
| `tb_talos_rename.vhd` | `talos_rename.vhd`, `talos_rat.vhd`, `talos_free_list.vhd`, `talos_checkpoint.vhd` | Speculative RAT allocation, intra-cycle RAW forwarding between dual instructions, snapshot checkpoint restore. |
| `tb_talos_rs.vhd` | `talos_rs_alu.vhd`, `talos_rs_mem.vhd`, `talos_rs_muldiv.vhd`, `talos_rs_fpu.vhd` | Distributed RS entry allocation, CDB operand wakeup, oldest-first grant arbitration. |
| `tb_talos_rob.vhd` | `talos_rob.vhd` | Circular buffer index management, speculative state tracking, dual-way in-order retirement, exception squashing. |
| `tb_talos_lsq.vhd` | `talos_lsq.vhd` | Circular LQ/SQ queues, age-ordered store-to-load byte forwarding, memory disambiguation hazard squashes. |
| `tb_talos_dcache.vhd` | `talos_dcache.vhd`, `talos_mshr.vhd` | 4-way tag lookup, hit-under-miss concurrency, MSHR allocation and merge, dirty line eviction, AXI4 burst refills. |
| `tb_talos_core.vhd` | `talos_core.vhd` | Integrated out-of-order CPU pipeline, instruction decode, out-of-order execution, precise exception handling. |
| `tb_talos_soc.vhd` | `talos_soc.vhd` | Full SoC system, AXI4 crossbar arbitration, BRAM memory, UART transmissions, CLINT timer interrupts. |

---

## 3. C++20 Cycle-Accurate Golden Simulator

Located in `tools/emulator/`, the C++20 golden simulator provides an architectural reference for verification:
- **ELF Loader** (`talos_elf.cpp`): Direct ingestion of RV32IMF ELF binaries, parsing 32-bit ELF headers, program headers, and symbol tables.
- **Instruction Disassembler** (`talos_disasm.cpp`): Real-time instruction decoding with disassembled assembly output.
- **Execution Engine** (`talos_emu.cpp`): Models architectural register state, CSR bank, memory hierarchy, and peripherals with exact compliance to the RISC-V specification.
- **Cycle-by-Cycle Tracing**: Generates a standardized execution trace recording program counter, instruction opcode, destination register value, and memory access addresses.

### Building the Golden Emulator
```bash
make emu
# Outputs compiled binary to bin/talos_emu
```

### Running an ELF Binary on the Emulator
```bash
./bin/talos_emu --elf=sw/build/test_quicksort.elf --max-cycles=50000 --trace=quicksort.trace
```

---

## 4. Automated Trace Differ and Discrepancy Localization

The Python trace comparison tool (`tools/harness/trace_differ.py`) performs lockstep comparison between VHDL simulation traces and C++ emulator golden traces:
- **State Fields Checked**: Architectural register write commits (`rd`, `data`), memory store commits (`addr`, `data`, `mask`), and CSR modifications (`csr_addr`, `val`).
- **Out-of-Order Retirement Matching**: Compares state strictly at the commit point to decouple internal speculative scheduling differences from architectural outcome.
- **Error Localization**: Pinpoints the exact cycle, PC, instruction, and divergent bit on mismatch.

---

## 5. Software Regression Suite and Benchmarks

The software suite in `sw/` exercises both basic pipeline functionality and demanding compute benchmarks:

### Functional Unit and ISA Tests (`sw/tests/`)
1. `test_alu.c`: Exhaustive arithmetic, bitwise logic, and barrel shift patterns.
2. `test_branch.c`: Conditional branches, loops, backwards/forwards branches, and target prediction stress.
3. `test_mem.c`: Byte, halfword, and word loads and stores with varying alignment offsets.
4. `test_muldiv.c`: Signed and unsigned 32x32 multiplications and divisions, including boundary conditions.
5. `test_fpu.c`: Single-precision arithmetic, multiply-accumulate, comparisons, and square root operations.
6. `test_quicksort.c`: Recursive in-place quicksort algorithm exercising heavy stack manipulation and memory traffic.
7. `test_gemm.c`: General matrix multiplication exercising inner-loop load-store throughput and register pressure.
8. `test_exception.c`: Illegal instruction handling, ECALL trap entry, and MRET return paths.
9. `test_csr.c`: Atomic read-and-set, read-and-clear operations on standard machine CSRs.
10. `test_hazards.c`: Intentionally dense RAW, WAR, and WAW hazard sequences designed to stress register renaming and CDB forwarding.

### Standardized Microarchitectural Benchmarks (`sw/benchmarks/`)
- **Dhrystone 2.1**: Integer compute and string manipulation benchmark measuring Dhrystones per second and DMIPS/MHz.
- **CoreMark**: Embedded benchmark exercising list processing, matrix manipulation, state machine transitions, and CRC calculation.
- **Quicksort**: Memory-intensive sorting benchmark evaluating cache hit rates and memory disambiguation efficiency.
- **GEMM**: Floating-point and integer linear algebra kernel measuring sustained FPU and ALU issue rates.
- **SHA-256**: Cryptographic hashing kernel stressing 32-bit bitwise logic and iterative scheduling.

---

## 6. Regression Test Runner (`tools/harness/runner.py`)

The automated Python regression runner orchestrates compilation and execution:

```bash
# Run all 13 VHDL testbenches
python3 tools/harness/runner.py --suite=all

# Run specific functional group
python3 tools/harness/runner.py --suite=unit
python3 tools/harness/runner.py --suite=core
python3 tools/harness/runner.py --suite=soc

# Run with waveform generation enabled (.vcd output)
python3 tools/harness/runner.py --suite=all --wave
```

---

## 7. Interactive Terminal Monitor (`tools/dashboard/talos_monitor.py`)

For real-time pipeline visualization, Talos includes an interactive curses-based terminal monitor:
- Displays live pipeline stage status (IF, ID, RN, DP, IS, EX, ME, CM).
- Visualizes Reorder Buffer (ROB) occupancy, head/tail pointers, and commit activity.
- Graphs reservation station queues and Common Data Bus broadcasts.
- Computes real-time Instructions Per Cycle (IPC) and branch prediction accuracy statistics.

```bash
python3 tools/dashboard/talos_monitor.py --trace=sim_output.trace
```
