# ==============================================================================
# Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
# CRT0: Low-Level Architecture Bootstrap and Execution Entrypoint
# Standard: RISC-V RV32IMF Assembly
# ==============================================================================

    .section .text.init
    .globl _start
    .type _start, @function

_start:
    # 1. Initialize integer register file to deterministic zero
    li  x1, 0
    li  x2, 0
    li  x3, 0
    li  x4, 0
    li  x5, 0
    li  x6, 0
    li  x7, 0
    li  x8, 0
    li  x9, 0
    li  x10, 0
    li  x11, 0
    li  x12, 0
    li  x13, 0
    li  x14, 0
    li  x15, 0
    li  x16, 0
    li  x17, 0
    li  x18, 0
    li  x19, 0
    li  x20, 0
    li  x21, 0
    li  x22, 0
    li  x23, 0
    li  x24, 0
    li  x25, 0
    li  x26, 0
    li  x27, 0
    li  x28, 0
    li  x29, 0
    li  x30, 0
    li  x31, 0

    # 2. Setup global pointer (gp) and stack pointer (sp)
.option push
.option norelax
    la  gp, __global_pointer$
.option pop
    la  sp, __stack_top

    # 3. Enable FPU extension in mstatus (FS field = bits 14:13 = 01)
    li  t0, 0x00002000
    csrs mstatus, t0

    # 4. Clear uninitialized BSS section
    la  t0, __bss_start
    la  t1, __bss_end
bss_clear_loop:
    bgeu t0, t1, bss_clear_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    bss_clear_loop
bss_clear_done:

    # 5. Install default trap vector handler
    la   t0, _trap_handler
    csrw mtvec, t0

    # 6. Branch to main application
    li   a0, 0      # argc = 0
    li   a1, 0      # argv = NULL
    call main

    # 7. Write return code to TOHOST communication address
    # a0 contains main() exit code
    li   t0, 0x80001000
    bnez a0, sim_fail
    li   t1, 1      # 1 indicates test PASS
    sw   t1, 0(t0)
    j    sim_halt

sim_fail:
    slli a0, a0, 1
    ori  a0, a0, 1  # (code << 1) | 1 indicates test FAIL
    sw   a0, 0(t0)

sim_halt:
    wfi
    j    sim_halt

    .globl _trap_handler
    .type _trap_handler, @function
_trap_handler:
    # Save mepc to avoid infinite trap loops
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret
