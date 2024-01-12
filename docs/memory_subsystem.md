# Talos Memory Subsystem: Architecture and Verification

The memory hierarchy of the Talos processor is engineered to deliver high memory bandwidth and low effective load latency in the presence of dynamic out-of-order execution. The memory subsystem combines a split L1 cache architecture with a decoupled Load-Store Queue (LSQ), speculative store-to-load byte forwarding crossbar, memory disambiguation violation detection, an autonomous 4-entry Miss Status Holding Register (MSHR) controller, and an AXI4 system fabric.

---

## 1. Architectural Overview

```
                        +---------------------------------------+
                        |           Dispatch Stage              |
                        +---------------------------------------+
                                   |                 |
                   Alloc Load      |                 | Alloc Store
                                   v                 v
                        +-----------------+   +-----------------+
                        |   Load Queue    |   |   Store Queue   |
                        |   (16 Entries)  |   |   (16 Entries)  |
                        +-----------------+   +-----------------+
                                   |                 |
                         AGU Exec  |                 | Store Commit
                                   v                 v
                        +---------------------------------------+
                        | Store-to-Load Byte Forwarding Crossbar|
                        +---------------------------------------+
                                   |                 |
                      Cache Access |                 | Write-Back Buffer
                                   v                 v
                        +---------------------------------------+
                        |        Non-Blocking L1 D-Cache        |
                        |     (8 KB, 4-Way Set-Associative)     |
                        +---------------------------------------+
                                   |                 ^
                        Miss Evict |                 | Refill Response
                                   v                 |
                        +---------------------------------------+
                        |      4-Entry MSHR Controller          |
                        +---------------------------------------+
                                           |
                               AXI4 Master | 32-Byte Bursts
                                           v
                        +---------------------------------------+
                        |        System AXI4 Interconnect       |
                        +---------------------------------------+
```

---

## 2. Decoupled Load-Store Queue (LSQ)

The Talos LSQ decouples address generation from physical memory access and consists of two distinct queues:
- **Load Queue (LQ)**: 16 entries organized as a circular FIFO tracking all in-flight speculative loads.
- **Store Queue (SQ)**: 16 entries organized as a circular FIFO tracking in-flight stores from dispatch until in-order retirement at the Reorder Buffer (ROB).

### Allocation and Deallocation
- During the Dispatch stage, load instructions allocate an entry at `lq_tail`, capturing their ROB index and destination physical register tag.
- Store instructions allocate an entry at `sq_tail`, capturing their ROB index, source data physical register tag, and store size (byte, halfword, word).
- Upon retirement in the Commit stage, confirmed stores drain from `sq_head` to initiate cache write-backs. When an exception or branch misprediction occurs, the queues roll back to the architectural snapshot pointer.

---

## 3. Speculative Store-to-Load Forwarding Crossbar

To eliminate load stalls behind in-flight stores writing to identical addresses, the LSQ integrates a combinational store-to-load forwarding crossbar operating at byte granularity.

### Forwarding Algorithm
When a load computes its effective address via the Memory Reservation Station (RS) and Address Generation Unit (AGU):
1. **Age-Ordered Scan**: The forwarding unit examines all older store entries between `sq_head` and the load's allocated store point.
2. **Byte Mask Matching**: For each older store matching the load word address (`addr[31:2]`):
   - Active store byte lanes (`store_mask[3:0]`) overwrite corresponding load byte lanes (`load_mask[3:0]`).
   - Forwarded data bytes are latched directly into the load response register.
3. **Completion Determination**:
   - **Full Forwarding**: If all required load bytes are provided by preceding stores, the load completes immediately without accessing the L1 data cache (zero-cycle forwarding penalty).
   - **Partial Forwarding**: If some bytes match but others remain unwritten by stores, the remaining bytes are concurrently retrieved from the L1 data cache and merged with the forwarded store bytes.
   - **No Match**: The load issues directly to the L1 data cache tag comparison stage.

```
Example: 32-bit Load with Overlapping Store
Load Address:  0x8000_1004 (Lw, mask = 1111b)
Older Store 1: 0x8000_1004 (Sb, mask = 0001b, byte 0 = 0xAA)
Older Store 2: 0x8000_1006 (Sh, mask = 1100b, bytes 2-3 = 0xBBCC)
Cache Read:    0x8000_1004 (Provides byte 1 = 0x11)
Merged Result: 0xBBCC_11AA (Delivered directly to Common Data Bus)
```

---

## 4. Memory Disambiguation and Violation Monitoring

Talos employs speculative memory disambiguation: loads are permitted to execute out of order before older store addresses are fully calculated.

### Violation Detection
If a store executes its AGU stage and calculates an effective address that matches an already-executed younger load in the Load Queue:
1. The memory disambiguation monitor flags an ordering hazard (`disambig_violation`).
2. The younger load entry in the LQ asserts its `hazard_replay` flag.
3. Upon reaching the head of the ROB, the offending load triggers a pipeline squash and replay, rolling back processor state to the pre-load checkpoint and refetching instructions in correct order.

This optimistic execution policy significantly increases instruction-level parallelism (ILP) in pointer-chasing and loop-dominated workloads where store-load collisions are statistically rare.

---

## 5. Non-Blocking L1 Data Cache Architecture

The L1 data cache (`talos_dcache.vhd`) is a non-blocking, write-back, write-allocate cache configured for high-concurrency memory accesses:
- **Capacity**: 8 KB
- **Associativity**: 4-way set-associative (64 sets, 32 bytes per line).
- **Replacement Policy**: Tree-based pseudo-LRU (PLRU) using 3 state bits per set.
- **Write Policy**: Write-back with dirty bit tracking and write-allocate on misses.

### Address Partitioning (32-Bit Address)
```
+---------------------------+-------------------+-----------------+
|         Tag (21 bits)     |   Index (6 bits)  |  Offset (5 bits)|
|         [31:11]           |       [10:5]      |      [4:0]      |
+---------------------------+-------------------+-----------------+
```

### Hit and Miss Processing Pipeline
1. **Cycle 1 (Tag Lookup)**: Synchronous SRAM arrays read tags and status bits across all four ways in parallel using `addr[10:5]`.
2. **Cycle 2 (Hit Select & Data Mux)**: Four 21-bit comparators compare stored tags against `addr[31:11]`.
   - On a **Hit**: Data word is selected via way multiplexer and returned to the LSQ within the same cycle.
   - On a **Miss**: The cache controller checks the Miss Status Holding Register (MSHR) bank.

---

## 6. Miss Status Holding Registers (MSHR)

To support hit-under-miss and miss-under-miss operations, the cache integrates a 4-entry MSHR controller (`talos_mshr.vhd`).

### MSHR Entry Organization
Each MSHR entry stores:
- Target line address (`tag + index`).
- Destination physical register tag and ROB identifier.
- Word offset and load sign-extension attributes.
- Primary vs. secondary miss indicators (allowing multiple load requests to the same in-flight cache line to merge into a single memory transaction).

### Servicing Workflow
1. When an L1 miss occurs and an MSHR entry is allocated, the cache signals the AXI4 master interface to initiate a 32-byte burst transaction (`ARLEN = 7`, `ARSIZE = 010`).
2. If the replaced line is marked **Dirty**, the cache simultaneously allocates an eviction buffer entry to write back the 32-byte modified line via an AXI4 write burst (`AWLEN = 7`, `AWSIZE = 010`).
3. While the burst refill is pending, subsequent load requests targeting other cached lines continue to hit without stalling the execution core (hit-under-miss).
4. As refill beats arrive over the AXI4 bus, they are assembled in a refill buffer. Once all 8 words (256 bits) are gathered, the cache tag and data arrays update, and the awaiting loads wake up and broadcast their data onto the Common Data Bus (CDB).

---

## 7. L1 Instruction Cache

The L1 instruction cache (`talos_icache.vhd`) provides a steady instruction stream to the front-end fetch queue:
- **Capacity**: 8 KB
- **Associativity**: 2-way set-associative (128 sets, 32 bytes per line).
- **Access Width**: 64 bits per cycle (two consecutive 32-bit instructions).
- **Refill Engine**: Dedicated AXI4 master burst read interface operating independently of the data cache.

---

## 8. AXI4 System Interconnect and Peripheral Fabric

Talos connects to memory and peripherals via an AXI4 crossbar hierarchy:
1. **AXI4-Full Cache Interconnect**: Bridges the L1 I-Cache and L1 D-Cache burst interfaces to external DDR or high-capacity system memory.
2. **AXI4-Lite Peripheral Crossbar**: Bridges single-word memory-mapped I/O transactions to:
   - **Boot ROM** (`0x0001_0000`): Contains reset bootstrap code and self-tests.
   - **Synchronous BRAM** (`0x8000_0000`): Primary low-latency scratchpad memory.
   - **16550 UART** (`0x1000_0000`): Full-duplex serial console with 16-byte FIFO buffers and baud rate generator.
   - **Core-Local Interruptor (CLINT)** (`0x0200_0000`): Provides 64-bit `mtime` and `mtimecmp` registers driving timer interrupt lines to the CPU core.
