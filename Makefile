# ==============================================================================
# Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
# High-Performance Build and Verification Orchestrator
# ==============================================================================

SHELL       := /bin/bash
CXX         := clang++
CXXFLAGS    := -std=c++20 -O3 -Wall -Wextra -pedantic -Itools/emulator
PYTHON      := python3

VHDL_STD    := 2008
BUILD_DIR   := build
BIN_DIR     := bin
OBJ_DIR     := obj

NVC         := $(shell which nvc 2>/dev/null)
GHDL        := $(shell which ghdl 2>/dev/null)

RTL_SRC     := $(shell find rtl -name "*.vhd" | sort)
SIM_SRC     := $(shell find sim -name "*.vhd" | sort)

.PHONY: all clean check test emu sim bench help

all: check emu test

help:
	@echo "Talos Out-of-Order Microarchitecture Build System"
	@echo "Targets:"
	@echo "  all      : Run static checks, build emulator, run tests"
	@echo "  check    : Perform strict syntax and structural analysis on VHDL RTL"
	@echo "  emu      : Build C++ cycle-accurate golden architectural emulator"
	@echo "  test     : Run unit and integration verification test suites"
	@echo "  sim      : Execute co-simulation trace diffing against golden model"
	@echo "  bench    : Run architectural performance benchmarks"
	@echo "  clean    : Remove all intermediate artifacts and build outputs"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR) $(BIN_DIR) $(OBJ_DIR)

check:
	@echo "[Talos] Running static verification and AST validation on VHDL sources..."
	@$(PYTHON) tools/harness/vhdl_linter.py rtl sim
	@echo "[Talos] VHDL source verification complete: 0 errors."

emu: $(BIN_DIR)/talos_emu

$(BIN_DIR)/talos_emu: tools/emulator/talos_emu.cpp tools/emulator/talos_disasm.cpp tools/emulator/talos_elf.cpp | $(BUILD_DIR)
	@echo "[Talos] Compiling cycle-accurate C++20 golden architectural emulator..."
	@$(CXX) $(CXXFLAGS) $^ -o $@
	@echo "[Talos] Emulator binary built at $@"

test: emu
	@echo "[Talos] Executing testbench regression suite..."
	@$(PYTHON) tools/harness/runner.py --suite=unit
	@$(PYTHON) tools/harness/runner.py --suite=integration
	@echo "[Talos] All verification tests PASSED (100% pass rate)."

sim: emu
	@echo "[Talos] Running cycle-accurate co-simulation with trace verification..."
	@$(PYTHON) tools/harness/trace_differ.py
	@echo "[Talos] Co-simulation verification PASSED with zero trace deviations."

bench: emu
	@echo "[Talos] Executing microarchitectural benchmark suite..."
	@$(PYTHON) tools/harness/runner.py --suite=benchmarks
	@echo "[Talos] Benchmark execution complete."

clean:
	@rm -rf $(BUILD_DIR) $(BIN_DIR) $(OBJ_DIR) work work-obj*.cf *.vcd *.ghw *.fst *.log
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "[Talos] Clean complete."
