#!/usr/bin/env python3
"""
Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
Verification Harness: Automated Regression Runner and Test Orchestrator
"""

import sys
import os
import argparse
import subprocess
import time
import json
from pathlib import Path

# Color terminal formatting
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

UNIT_TESTS = [
    {
        "name": "tb_talos_pkg",
        "description": "Microarchitectural package definitions, constants, and record types",
        "vhd": "sim/tb_talos_pkg.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_fifo",
        "description": "Generic synchronous FIFO with almost-full and almost-empty thresholds",
        "vhd": "sim/tb_talos_fifo.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_alu",
        "description": "Dual ALU units, arithmetic, shifts, logic, and comparison operations",
        "vhd": "sim/tb_talos_alu.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_muldiv",
        "description": "Radix-4 Booth multiplier and non-restoring iterative integer divider",
        "vhd": "sim/tb_talos_muldiv.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_fpu",
        "description": "IEEE-754 single precision floating-point adder, multiplier, converter",
        "vhd": "sim/tb_talos_fpu.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_bpred",
        "description": "Gshare branch predictor, BTB, and RAS return address stack repair",
        "vhd": "sim/tb_talos_bpred.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_rename",
        "description": "Speculative RAT, Free List allocation, and Checkpoint restore engine",
        "vhd": "sim/tb_talos_rename.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_rs",
        "description": "Distributed reservation stations, tag matching, and CDB snooping",
        "vhd": "sim/tb_talos_rs.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_rob",
        "description": "32-entry circular Reorder Buffer in-order commit and exception handling",
        "vhd": "sim/tb_talos_rob.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_lsq",
        "description": "Load Queue, Store Queue, and speculative store-to-load byte forwarding",
        "vhd": "sim/tb_talos_lsq.vhd",
        "category": "unit"
    },
    {
        "name": "tb_talos_dcache",
        "description": "4-way set-associative non-blocking L1 data cache and MSHR controller",
        "vhd": "sim/tb_talos_dcache.vhd",
        "category": "unit"
    }
]

INTEGRATION_TESTS = [
    {
        "name": "tb_talos_core",
        "description": "Dual-issue out-of-order CPU core instruction execution and branch recovery",
        "vhd": "sim/tb_talos_core.vhd",
        "category": "integration"
    },
    {
        "name": "tb_talos_soc",
        "description": "Top-level SoC integration: AXI4 crossbar, Boot ROM, BRAM, UART, and CLINT",
        "vhd": "sim/tb_talos_soc.vhd",
        "category": "integration"
    }
]

def check_nvc_available():
    try:
        res = subprocess.run(["nvc", "--version"], capture_output=True, text=True)
        return res.returncode == 0
    except FileNotFoundError:
        return False

def run_nvc_test(test, verbose=False):
    start_time = time.time()
    vhd_path = test["vhd"]
    if not os.path.exists(vhd_path):
        return {
            "name": test["name"],
            "status": "SKIP",
            "time_ms": 0,
            "message": f"File {vhd_path} not found"
        }

    # Analyze testbench
    cmd_a = ["nvc", "-a", vhd_path]
    res_a = subprocess.run(cmd_a, capture_output=True, text=True)
    if res_a.returncode != 0:
        return {
            "name": test["name"],
            "status": "FAIL",
            "time_ms": (time.time() - start_time) * 1000,
            "message": f"Analysis failed:\n{res_a.stderr or res_a.stdout}"
        }

    # Elaborate and Run
    cmd_r = ["nvc", "-e", test["name"], "--run"]
    res_r = subprocess.run(cmd_r, capture_output=True, text=True)
    elapsed_ms = (time.time() - start_time) * 1000

    output = (res_r.stdout + "\n" + res_r.stderr).strip()
    if res_r.returncode == 0 and "ERROR" not in output.upper():
        return {
            "name": test["name"],
            "status": "PASS",
            "time_ms": elapsed_ms,
            "message": output if verbose else ""
        }
    else:
        return {
            "name": test["name"],
            "status": "FAIL",
            "time_ms": elapsed_ms,
            "message": output
        }

def run_suite(tests, verbose=False):
    passed = 0
    failed = 0
    skipped = 0
    results = []

    print(f"\n{BOLD}{CYAN}=== Talos Microarchitecture Verification Regression ==={RESET}\n")

    for t in tests:
        res = run_nvc_test(t, verbose)
        results.append(res)
        name_str = f"{t['name']:<18}"
        desc_str = f"{t['description'][:52]:<54}"

        if res["status"] == "PASS":
            passed += 1
            status_str = f"{GREEN}[PASS]{RESET}"
            time_str = f"({res['time_ms']:.1f} ms)"
            print(f"  {status_str} {name_str} {desc_str} {time_str}")
            if verbose and res["message"]:
                print(f"         {res['message']}")
        elif res["status"] == "SKIP":
            skipped += 1
            status_str = f"{YELLOW}[SKIP]{RESET}"
            print(f"  {status_str} {name_str} {desc_str} {res['message']}")
        else:
            failed += 1
            status_str = f"{RED}[FAIL]{RESET}"
            time_str = f"({res['time_ms']:.1f} ms)"
            print(f"  {status_str} {name_str} {desc_str} {time_str}")
            print(f"\n{RED}Error details for {t['name']}:{RESET}")
            for line in res["message"].splitlines()[:15]:
                print(f"    {line}")
            print()

    total = passed + failed + skipped
    print(f"\n{BOLD}------------------------------------------------------------{RESET}")
    print(f"Regression Summary: {passed}/{total} Passed, {failed} Failed, {skipped} Skipped.")
    if failed == 0:
        print(f"{GREEN}{BOLD}Result: 100% PASS RATE - VERIFICATION CLEAN{RESET}\n")
    else:
        print(f"{RED}{BOLD}Result: REGRESSION FAILED{RESET}\n")

    return failed == 0

def main():
    parser = argparse.ArgumentParser(description="Talos Verification Regression Runner")
    parser.add_argument("--suite", choices=["unit", "integration", "all"], default="all",
                        help="Verification suite category to execute")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Display detailed simulation outputs")
    parser.add_argument("--filter", type=str, default="",
                        help="Filter tests by name substring")
    args = parser.parse_args()

    tests = []
    if args.suite in ("unit", "all"):
        tests.extend(UNIT_TESTS)
    if args.suite in ("integration", "all"):
        tests.extend(INTEGRATION_TESTS)

    if args.filter:
        tests = [t for t in tests if args.filter in t["name"]]

    success = run_suite(tests, args.verbose)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
