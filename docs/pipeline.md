# Talos Pipeline Architecture: 8-Stage Out-of-Order Execution

The Talos processor core decomposes instruction execution into an 8-stage superscalar out-of-order execution pipeline. The pipeline cleanly decouples the front-end fetch and in-order decode/rename/dispatch engines from the out-of-order execution core and in-order retirement commit unit.

---

## 1. Pipeline Stage Overview

```
+----+     +----+     +----+     +----+     +----+     +----+     +----+     +----+
| IF | --> | ID | --> | RN | --> | DP | --> | IS | --> | EX | --> | ME | --> | CM |
+----+     +----+     +----+     +----+     +----+     +----+     +----+     +----+
Fetch      Decode     Rename     Dispatch   Issue      Execute    Memory     Commit
```

---

## 2. Stage-by-Stage Operational Walkthrough

### Stage 1: Instruction Fetch (IF)
- **Decoupled PC Generation**: The `talos_pc_gen` module arbitrates between four next-PC sources:
  1. Trap and exception redirect vectors from the Commit stage.
  2. Branch misprediction recovery targets from the Branch Resolution Unit.
  3. Speculative branch and jump targets from the BTB, Gshare, and RAS.
  4. Sequential PC increment (`PC + 8` for dual-instruction fetch).
- **L1 Instruction Cache**: 2-way set-associative 8 KB cache. Reads 64 bits (two 32-bit instructions) per clock cycle. On a cache miss, an autonomous burst refill FSM generates an AXI4-Full 32-byte burst transaction to system memory.
- **Dynamic Branch Prediction**:
  - Gshare predictor accesses a 1024-entry Pattern History Table (PHT) indexed by `PC[11:2] XOR GHR[9:0]`.
  - 2-way Branch Target Buffer (BTB) provides predicted branch and jump target addresses.
  - 16-entry Return Address Stack (RAS) predicts subroutine return addresses (`ret` / `jalr x0, x1, 0`).
- **Fetch Buffer**: A FIFO decoupling the front-end fetch rate from variable decode and dispatch stalls.

### Stage 2: Instruction Decode (ID)
- **Dual-Way Decoding**: Two parallel decoders (`talos_decoder`) unpack instruction bundles into internal micro-operations (`decode_pkt_t`).
- **Field Extraction**: Extracts architectural register indices (`rs1`, `rs2`, `rs3`, `rd`), immediate values, and functional unit classifications (`fu_type_t`).
- **Pre-Decode and Traps**: Identifies illegal instructions, ECALL, EBREAK, FENCE, and CSR accesses.

### Stage 3: Register Rename (RN)
- **Physical Register Allocation**: Interacts with the `talos_free_list` to obtain physical registers for instructions defining an architectural destination register.
- **Speculative RAT Mapping**: Maps architectural register identifiers to physical register tags.
- **Intra-Cycle Forwarding**: If instruction 0 defines register `rd` and instruction 1 reads the same register as `rs1` or `rs2`, intra-cycle bypass assigns the newly allocated physical register tag of instruction 0 directly to instruction 1, eliminating pipeline bubbles.
- **Speculative Checkpointing**: When a conditional branch or jump is renamed, the 8-entry Checkpoint Store (`talos_checkpoint`) captures a single-cycle snapshot of:
  - The complete 32-entry sRAT table.
  - The Free List allocation head pointer.
  - The Branch History Register (BHR) and Return Address Stack (RAS) top-of-stack pointer.

### Stage 4: Dispatch (DP)
- **Structural Hazard Detection**: Verifies space availability across:
  - The 32-entry Reorder Buffer (ROB).
  - Target distributed Reservation Stations (ALU, MulDiv, Memory, or FPU).
  - The Load-Store Queue (LQ for loads, SQ for stores).
- **Resource Allocation**: Injects instructions into the tail of the ROB, inserts memory operations into the LSQ, and routes instructions to their appropriate reservation stations.

### Stage 5: Issue (IS)
- **Distributed Reservation Stations**:
  - `talos_rs_alu` (8 entries): ALU and Branch operations.
  - `talos_rs_muldiv` (4 entries): Hardware integer multiplication and division.
  - `talos_rs_mem` (8 entries): Memory address generation and loads/stores.
  - `talos_rs_fpu` (4 entries): Single-precision floating-point arithmetic.
- **Common Data Bus Wakeup**: Reservation station slots continuously snoop the 5-channel Common Data Bus (CDB). When a broadcast tag matches a pending operand tag, the corresponding ready bit is asserted.
- **Arbitration**: Age-based priority encoders pick the oldest ready instructions each cycle to issue to execution units.

### Stage 6: Execute (EX)
- **Multi-Port Physical Register File Read**: Operands are fetched from the 64-entry PRF.
- **Execution Units**:
  - ALU 0 and Branch Unit (single-cycle arithmetic, logic, and branch condition evaluation).
  - ALU 1 (single-cycle integer ALU).
  - Multiplier (3-stage pipelined radix-4 Booth multiplier).
  - Divider (32-cycle non-restoring iterative integer divider).
  - Floating-Point Unit (pipelined IEEE-754 adder, multiplier, and conversion blocks).
- **CDB Priority Arbitration**: Results from all functional units are arbitrated onto the 5-channel Common Data Bus and broadcast to the PRF, ROB, and Reservation Stations.

### Stage 7: Memory Access (ME)
- **Address Generation**: Computes effective memory addresses (`rs1 + immediate`).
- **Store-to-Load Forwarding**: The Load-Store Queue checks active store queue entries for address overlaps. If a match occurs with full byte coverage, data is forwarded directly without accessing the L1 data cache.
- **Disambiguation Violation Monitor**: Verifies that younger loads executed out-of-order did not read stale data before an older store with an overlapping address completed.
- **Non-Blocking D-Cache**: Handles cache hits in 2 cycles. Cache misses allocate one of 4 MSHR slots, initiating an AXI4 burst line refill while allowing hit accesses to proceed.

### Stage 8: Commit (CM)
- **In-Order Retirement**: Up to two instructions retire per cycle from the head of the 32-entry circular Reorder Buffer.
- **Architectural State Update**:
  - Updates the Committed Register Alias Table (cRAT).
  - Frees the overwritten physical register tag, returning it to the Free List.
  - Retires stores from the Store Queue, authorizing write-back into the L1 data cache.
  - Retires CSR instructions, updating machine-mode status and control registers.
- **Precise Exception Handling**: If an instruction encounters an exception (e.g. illegal instruction, misaligned access, ECALL), retirement halts when that instruction reaches the head of the ROB. Speculative state is purged, and the PC redirects to the trap vector (`mtvec`).
