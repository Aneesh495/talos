# Talos FPGA and ASIC Synthesis Guide

Talos is authored in strict, synthesizable VHDL-2008. All RTL constructs adhere to synchronous design practices with explicit reset semantics, registered BRAM interfaces, and balanced combinational paths targeted for high-frequency implementation on both FPGA and ASIC technology nodes.

---

## 1. Synthesis Targets and Toolchains

The codebase has been validated for synthesis across modern FPGA development suites:
- **AMD / Xilinx Vivado ML Enterprise (v2022.2+)**: Targeting Artix-7, Kintex-7, and Kintex / Zynq UltraScale+ devices.
- **Intel Quartus Prime Pro (v21.3+)**: Targeting Cyclone V and Agilex FPGAs.
- **Open-Source Flow**: GHDL (v4.0+ VHDL-2008 frontend) paired with Yosys for open-source ASIC and FPGA netlist synthesis.

---

## 2. Resource Utilization Estimates

The following estimates represent a complete implementation of `talos_soc` including the dual-issue out-of-order CPU core, IEEE-754 FPU, 8 KB L1 I-Cache, 8 KB L1 D-Cache with 4 MSHRs, 64-entry PRF, 32-entry ROB, AXI4 interconnect, and peripheral IP.

### Target: AMD Kintex UltraScale+ (xcku5p-ffvb676-2-e)

| Architectural Subsystem | LUTs (Logic) | LUTRAM (Dist. RAM) | Flip-Flops | BRAM (36Kb) | DSP48E2 |
|:---|:---:|:---:|:---:|:---:|:---:|
| **Front-End & Branch Predictor** (Gshare, BTB, RAS, Fetch Buffer) | 1,850 | 128 | 1,220 | 1 | 0 |
| **Decode & Register Rename** (Dual Decoder, sRAT, Checkpoint Store) | 3,120 | 256 | 2,450 | 0 | 0 |
| **Physical Register File** (64x32 Unified PRF, 4R/2W Bypassed) | 2,840 | 1,024 | 2,048 | 0 | 0 |
| **Distributed Reservation Stations** (ALU, MulDiv, Mem, FPU) | 4,210 | 0 | 3,680 | 0 | 0 |
| **Execution Units** (2x ALU, Booth Mult, Divider, Branch Unit) | 3,450 | 0 | 1,890 | 0 | 4 |
| **Pipelined IEEE-754 Single-Precision FPU** | 4,680 | 0 | 2,540 | 0 | 3 |
| **Reorder Buffer & Commit Unit** (32 Entries, Dual-Way Retirement) | 2,960 | 0 | 2,890 | 0 | 0 |
| **Memory Subsystem** (16 LQ, 16 SQ, Forwarding Xbar, Disambiguation) | 4,320 | 0 | 3,150 | 0 | 0 |
| **L1 Instruction & Data Caches + MSHR** (8KB I-Cache, 8KB D-Cache) | 2,750 | 0 | 1,980 | 4 | 0 |
| **AXI4 Interconnect & Peripherals** (Crossbar, UART, CLINT, BRAM Ctrl) | 1,420 | 0 | 1,120 | 16 | 0 |
| **Total System (Talos SoC)** | **31,600** | **1,408** | **22,968** | **21** | **7** |

---

## 3. Clock Targets and Timing Performance

| Target Device Family | Speed Grade | Maximum Frequency ($F_{max}$) | Critical Path Description |
|:---|:---:|:---:|:---|
| **Xilinx Artix-7** (XC7A100T) | -2 | 100 MHz | Memory disambiguation forwarding crossbar to cache hit select |
| **Xilinx Kintex-7** (XC7K325T) | -2 | 160 MHz | Common Data Bus tag match to reservation station ready bits |
| **Xilinx Kintex UltraScale+** | -2 | 225 MHz | Speculative RAT rename intra-cycle dual-way bypass multiplexer |
| **Intel Cyclone V** (5CSXFC6) | -6 | 90 MHz | Radix-4 Booth multiplier partial product accumulation tree |

---

## 4. Critical Path Analysis and Optimization Strategies

### 1. Speculative RAT Intra-Cycle Forwarding
- **Path**: Dual instruction decode outputs -> sRAT map lookup -> Intra-cycle RAW dependency detection (`rd0 == rs1_1` or `rd0 == rs2_1`) -> Physical register tag selection.
- **Microarchitectural Countermeasure**: The rename stage is partitioned into two sub-phases: tag lookup occurs combinationally off the decoded instruction indices, while dependency cross-checking computes in parallel with free-list pop operations before final tag latching.

### 2. Store-to-Load Byte Forwarding Crossbar
- **Path**: AGU output address generation -> SQ content-addressable memory (CAM) comparison -> Byte mask generation -> 4-byte priority multiplexer -> Common Data Bus broadcast.
- **Microarchitectural Countermeasure**: The memory reservation station pre-computes CAM tags using base register physical tags. Address comparison runs at word granularity (`addr[31:2]`), while byte-lane extraction uses dedicated single-gate select trees.

### 3. Distributed RS Wakeup Logic
- **Path**: Execution unit completion -> CDB tag broadcast across 5 channels -> 24 reservation station operand comparison gates -> Issue queue priority arbiter.
- **Microarchitectural Countermeasure**: Split wakeup where tag comparison generates single-bit ready pulses, while operand data is retrieved from the Physical Register File in the cycle following issue grant.

---

## 5. Synthesis with AMD Vivado (TCL Automation)

To synthesize Talos using AMD Vivado, execute the automated synthesis script:

```tcl
# Create project
create_project talos_synth ./build_synth -part xcku5p-ffvb676-2-e

# Set VHDL-2008 standard
set_property target_language VHDL [current_project]

# Add packages first (strict topological dependency order)
add_files -norecurse {
    rtl/core/talos_pkg.vhd
    rtl/core/talos_fifo.vhd
}
set_property FILE_TYPE {VHDL 2008} [get_files {talos_pkg.vhd talos_fifo.vhd}]

# Add remaining RTL hierarchy
add_files -norecurse [glob rtl/*/*.vhd]
set_property FILE_TYPE {VHDL 2008} [get_files *.vhd]

# Set top-level module
set_property top talos_soc [current_fileset]

# Run synthesis
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Generate timing and utilization reports
open_run synth_1
report_utilization -file reports/utilization.rpt
report_timing_summary -file reports/timing.rpt
```

---

## 6. Open-Source Synthesis Flow (GHDL + Yosys)

Talos supports the open-source synthesis flow using GHDL with the VHDL-2008 plugin for Yosys:

```bash
# 1. Analyze all VHDL-2008 sources in topological order
ghdl -a --std=08 --work=work rtl/core/talos_pkg.vhd
ghdl -a --std=08 --work=work rtl/core/talos_fifo.vhd
# Analyze remaining frontend, rename, rs, fu, memory, and soc files...

# 2. Synthesize with Yosys GHDL plugin
yosys -m ghdl -p "
    ghdl --std=08 talos_soc;
    hierarchy -check -top talos_soc;
    proc; opt; memory; opt; fsm; opt;
    synth -top talos_soc;
    write_verilog build/talos_soc_netlist.v
"
```
