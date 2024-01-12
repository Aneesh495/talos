# Talos Microarchitecture: System Architecture and Specification

Talos is a synthesizable, dual-issue speculative out-of-order execution processor core implementing the RISC-V RV32IMF instruction set architecture in strict VHDL-2008. The microarchitecture employs explicit register renaming with a unified physical register file (MIPS R10k / Alpha 21264 style), distributed reservation stations, a circular reorder buffer supporting precise architectural exceptions, speculative branch checkpointing, and a high-performance non-blocking memory subsystem with store-to-load forwarding and miss status holding registers (MSHRs).

---

## 1. Architectural Highlights

- **Instruction Set**: RISC-V RV32IMF (User-level ISA version 20191213) plus Machine-Mode Privileged Architecture (version 20211203) with full Zicsr control/status register support.
- **Fetch Width**: Dual-instruction (64-bit) decoupled fetch with 8-entry instruction fetch queue.
- **Branch Prediction**:
  - Combined Gshare dynamic two-level predictor (1024-entry pattern history table, 10-bit global history register).
  - 2-way set-associative Branch Target Buffer (128 sets, 256 entries).
  - 16-entry Return Address Stack (RAS) with speculative top-of-stack recovery.
- **Execution Paradigm**: Out-of-order execution with in-order retirement using an explicit Physical Register File (PRF).
- **Register Renaming**: Speculative Register Alias Table (RAT) supporting intra-cycle dual-instruction RAW forwarding and 8-entry snapshot checkpoints for single-cycle branch misprediction recovery.
- **Physical Register File**: 64 physical registers (32 architectural baseline + 32 speculative in-flight registers) with multi-port write bypass.
- **Execution Windows**:
  - 32-entry circular Reorder Buffer (ROB) supporting dual-instruction in-order commit.
  - Distributed reservation stations: 8-entry ALU/Branch, 4-entry Multiplier/Divider, 8-entry Memory, 4-entry Floating-Point Unit.
- **Functional Units**:
  - Two 32-bit single-cycle integer ALUs.
  - Dedicated Branch Resolution Unit.
  - 3-stage pipelined radix-4 Booth multiplier.
  - Non-restoring iterative integer hardware divider.
  - Pipelined IEEE-754 single-precision floating-point unit (FADD, FSUB, FMUL, FDIV, FSQRT, conversions, comparisons).
- **Memory Subsystem**:
  - 16-entry Load Queue (LQ) and 16-entry Store Queue (SQ).
  - Speculative byte-level store-to-load forwarding crossbar with arbitrary sub-word alignment.
  - Memory order disambiguation violation monitor with pipeline replay trigger.
  - 8 KB 4-way set-associative non-blocking L1 data cache with 4-entry MSHR controller and pseudo-LRU replacement tree.
  - 8 KB 2-way set-associative L1 instruction cache with burst refill engine.
- **System Fabric**:
  - Full AXI4-Full master burst controller for cache line refills and evictions.
  - AXI4-Lite crossbar interconnect interfacing on-chip Boot ROM, high-speed synchronous BRAM, 16550-compatible UART, and 64-bit CLINT real-time timer.

---

## 2. Microarchitectural Block Diagram

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
|            |                                             | Dual-Issue Dispatch    |   |
|            |                                             | (ROB & LSQ Allocation) |   |
|            |                                             +------------------------+   |
|            |                                                         |                |
|            |         +-----------------------+-----------------------+                |
|            |         |                       |                       |                |
|            |         v                       v                       v                |
|            |   +-----------+           +-----------+           +-----------+          |
|            |   | ALU/BR RS |           | MulDiv RS |           | Memory RS |          |
|            |   | (8 slots) |           | (4 slots) |           | (8 slots) |          |
|            |   +-----------+           +-----------+           +-----------+          |
|            |         |                       |                       |                |
|            |         v                       v                       v                |
|            |   +-----------+           +-----------+           +-----------+          |
|            |   | ALU0 / BR |           | Radix-4 * |           | AGU / LSQ |          |
|            |   | ALU1 Unit |           | Iter Div  |           | (16L/16S) |          |
|            |   +-----------+           +-----------+           +-----------+          |
|            |         |                       |                       |                |
|            |         +-----------------------+-----------------------+                |
|            |                                 |                                        |
|            |                                 v                                        |
|            |                   +---------------------------+                          |
|            |                   | Common Data Bus Arbiter   |                          |
|            |                   | (5-Channel CDB Broadcast) |                          |
|            |                   +---------------------------+                          |
|            |                      |          |         |                              |
|            |       +--------------+          |         +-------------+                |
|            |       v                         v                       v                |
|            |   +--------+               +----------+            +---------+           |
|            |   | 64-reg |               | 32-Entry |            | 8KB L1  |           |
|            |   |  PRF   |               |   ROB    |            | D-Cache |           |
|            |   +--------+               +----------+            +---------+           |
|            |                                 |                       |                |
|            +---------------------------------+                       |                |
|                                                                      v                |
|                                                       +---------------------------+   |
|                                                       | AXI4-Full Master Bridge   |   |
+-------------------------------------------------------+---------------------------+---+
                                                                       |
                                                                       v
                                                       +---------------------------+
                                                       | AXI4 Interconnect Xbar    |
                                                       +---------------------------+
                                                         |       |       |       |
                                                         v       v       v       v
                                                       [ROM]   [RAM]   [UART]  [CLINT]
```

---

## 3. Execution Latency and Throughput Specifications

| Functional Unit | Target Operations | Latency (Cycles) | Issue Rate (Pipelined) | Common Data Bus Channel |
| :--- | :--- | :--- | :--- | :--- |
| **ALU 0** | ADD, SUB, shifts, logic, compares, jumps | 1 | 1 inst/cycle | Channel 0 |
| **ALU 1** | ADD, SUB, shifts, logic, compares | 1 | 1 inst/cycle | Channel 1 |
| **Branch Unit** | BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR | 1 | 1 inst/cycle | Channel 0 |
| **Multiplier** | MUL, MULH, MULHSU, MULHU | 3 | 1 inst/cycle | Channel 2 |
| **Divider** | DIV, DIVU, REM, REMU | 32 (non-restoring) | 1 per 32 cycles | Channel 3 |
| **FPU Adder** | FADD.S, FSUB.S | 3 | 1 inst/cycle | Channel 4 |
| **FPU Multiplier** | FMUL.S | 3 | 1 inst/cycle | Channel 4 |
| **FPU Misc** | FCVT, FEQ, FLT, FLE, FMIN, FMAX | 1 | 1 inst/cycle | Channel 4 |
| **Load Unit** | LB, LH, LW, LBU, LHU (L1 hit / forward) | 2 | 1 inst/cycle | Channel 4 |
| **Store Unit** | SB, SH, SW (Store Queue buffer) | 1 (retire to L1)| 1 inst/cycle | Internal LSQ / D-Cache |

---

## 4. Register Renaming Paradigm

Talos implements an explicit physical register renaming scheme:
- 32 architectural registers (`x0` through `x31`) are mapped to a pool of 64 physical registers (`p0` through `p63`).
- At system reset, architectural register `xi` is mapped to physical register `pi` in both the Speculative Register Alias Table (sRAT) and the Committed Register Alias Table (cRAT).
- Physical registers `p32` through `p63` are initialized into the Physical Register Free List.
- When an instruction with a destination register is dispatched:
  1. A new physical register `P_new` is popped from the Free List.
  2. The old mapping `P_old` in the sRAT is recorded in the allocated Reorder Buffer entry.
  3. The sRAT mapping is updated to `P_new`.
- When an instruction commits in the Reorder Buffer:
  1. The cRAT mapping is permanently updated to `P_new`.
  2. The old physical register `P_old` is reclaimed and pushed back onto the Free List.
- If a branch misprediction occurs:
  - The sRAT restores its complete state in a single clock cycle from the checkpoint snapshot captured when the branch was renamed.
  - Speculatively popped free registers are rolled back using the checkpoint allocation pointer.
