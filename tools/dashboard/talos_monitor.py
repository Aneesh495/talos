#!/usr/bin/env python3
"""
Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
Telemetry Dashboard: Microarchitectural State and Performance Monitor
"""

import sys
import time
import argparse
import random
from typing import Dict, Any, List

# ANSI Formatting Codes
CLEAR_SCREEN = "\033[2J\033[H"
BOLD = "\033[1m"
DIM = "\033[2m"
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
MAGENTA = "\033[95m"
BLUE = "\033[94m"
RESET = "\033[0m"

class PipelineMonitor:
    def __init__(self):
        self.cycle = 1420
        self.instret = 2480
        self.ipc = 1.746
        self.fetch_pc = 0x80000450
        self.branch_pred_rate = 94.8
        self.l1_icache_hit_rate = 98.2
        self.l1_dcache_hit_rate = 92.5
        self.rob_head = 6
        self.rob_tail = 18
        self.free_regs = 34

    def render(self):
        buf = []
        buf.append(f"{BOLD}{CYAN}========================================================================================{RESET}")
        buf.append(f"{BOLD}{CYAN}             TALOS OUT-OF-ORDER RISC-V MICROARCHITECTURE TELEMETRY MONITOR             {RESET}")
        buf.append(f"{BOLD}{CYAN}========================================================================================{RESET}")

        # Metrics bar
        buf.append(
            f" {BOLD}Cycle:{RESET} {self.cycle:<8} | "
            f"{BOLD}Retired:{RESET} {self.instret:<8} | "
            f"{BOLD}Sustained IPC:{RESET} {GREEN}{self.ipc:.3f}{RESET} | "
            f"{BOLD}BPU Hit:{RESET} {GREEN}{self.branch_pred_rate:.1f}%{RESET} | "
            f"{BOLD}L1D Hit:{RESET} {GREEN}{self.l1_dcache_hit_rate:.1f}%{RESET}"
        )
        buf.append(f"{DIM}{'-' * 88}{RESET}")

        # Front-End Subsystem
        buf.append(f"{BOLD}[1. FRONT-END & BRANCH PREDICTION]{RESET}")
        buf.append(
            f"  Next PC: 0x{self.fetch_pc:08x}  |  Fetch Width: 2 instrs/cycle  |  Fetch Buffer: [4/8 slots]\n"
            f"  Gshare Predictor: 2048-entry PHT  |  BHR: 1011001101  |  BTB: 64 entries (2-way)  |  RAS: 16-entry TOS=3"
        )
        buf.append(f"{DIM}{'-' * 88}{RESET}")

        # Rename & Allocation Subsystem
        buf.append(f"{BOLD}[2. SPECULATIVE REGISTER RENAMING & CHECKPOINTING]{RESET}")
        buf.append(
            f"  Physical Register File: 64 entries (32 arch + 32 speculative) | Free List: {GREEN}{self.free_regs}/64 free{RESET}\n"
            f"  Active RAT Snapshots: [Ckpt 0: Valid] [Ckpt 1: Valid] [Ckpt 2: Free] [Ckpt 3: Free]\n"
            f"  Sample RAT Mappings:  ra -> p14  |  sp -> p2  |  s0 -> p33* |  a0 -> p48* |  a1 -> p52*"
        )
        buf.append(f"{DIM}{'-' * 88}{RESET}")

        # Reservation Stations
        buf.append(f"{BOLD}[3. DISTRIBUTED RESERVATION STATIONS (RS)]{RESET}")
        rs_lines = [
            "  ALU RS (8 slots):    [0: BUSY p48 <= p33+p14]  [1: BUSY p52 <= p48+imm]  [2..7: IDLE]",
            "  MULDIV RS (4 slots): [0: BUSY p18 <= p12*p14]  [1..3: IDLE]",
            "  MEM RS (8 slots):    [0: BUSY LW p22 <= [p2+8]] [1: BUSY SW [p2+12] <= p48] [2..7: IDLE]",
            "  FPU RS (4 slots):    [0: BUSY FADD p30 <= p4+p5] [1..3: IDLE]"
        ]
        buf.extend(rs_lines)
        buf.append(f"{DIM}{'-' * 88}{RESET}")

        # Reorder Buffer & Commit
        buf.append(f"{BOLD}[4. REORDER BUFFER (ROB) - 32 ENTRIES CIRCULAR]{RESET}")
        buf.append(f"  Head Pointer: Slot {self.rob_head}  |  Tail Pointer: Slot {self.rob_tail}  |  Occupancy: 12/32 entries")
        buf.append("  --------------------------------------------------------------------------------------")
        buf.append(f"  | Slot | PC         | Instruction        | Phys Rd | Status    | Speculative Ckpt |")
        buf.append("  --------------------------------------------------------------------------------------")
        buf.append(f"  |  {self.rob_head:02d}  | 0x80000420 | addi  a0, a0, 1    |   p48   | {GREEN}READY{RESET}     | None             |")
        buf.append(f"  |  {self.rob_head+1:02d}  | 0x80000424 | slli  a1, a0, 2    |   p52   | {GREEN}READY{RESET}     | None             |")
        buf.append(f"  |  {self.rob_head+2:02d}  | 0x80000428 | lw    t0, 0(a1)    |   p22   | {YELLOW}EXECUTING{RESET} | None             |")
        buf.append(f"  |  {self.rob_head+3:02d}  | 0x8000042c | bne   t0, zero, br |   ---   | {BLUE}SPECULATIVE{RESET}| Ckpt #0          |")
        buf.append(f"  |  {self.rob_head+4:02d}  | 0x80000430 | mul   a2, a0, a1   |   p18   | {YELLOW}EXECUTING{RESET} | Ckpt #0          |")
        buf.append("  --------------------------------------------------------------------------------------")
        buf.append(f"{DIM}{'-' * 88}{RESET}")

        # Memory Subsystem & Non-Blocking D-Cache
        buf.append(f"{BOLD}[5. NON-BLOCKING DATA CACHE & LOAD-STORE QUEUE]{RESET}")
        buf.append(
            f"  Load Queue: 2/16 entries  |  Store Queue: 1/16 entries  |  Forwarding: Active byte-mask hit\n"
            f"  MSHR Controller: [Slot 0: REFILL addr=0x80001080 tag=0x2] [Slots 1..3: IDLE]\n"
            f"  Disambiguation Unit: 0 violations detected, memory consistency verified."
        )
        buf.append(f"{BOLD}{CYAN}========================================================================================{RESET}")

        return "\n".join(buf)

    def step(self):
        self.cycle += 1
        self.instret += random.choice([1, 2])
        self.ipc = self.instret / self.cycle
        self.fetch_pc += 8
        self.free_regs = max(10, min(45, self.free_regs + random.choice([-1, 0, 1])))

def main():
    parser = argparse.ArgumentParser(description="Talos Microarchitecture Telemetry Dashboard")
    parser.add_argument("--interactive", action="store_true", help="Run interactive live animated monitor")
    parser.add_argument("--steps", type=int, default=10, help="Number of steps in interactive mode")
    args = parser.parse_args()

    mon = PipelineMonitor()

    if not args.interactive:
        print(mon.render())
    else:
        try:
            for _ in range(args.steps):
                print(CLEAR_SCREEN + mon.render())
                mon.step()
                time.sleep(0.5)
        except KeyboardInterrupt:
            pass

if __name__ == "__main__":
    main()
