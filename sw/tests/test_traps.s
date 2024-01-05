# ==============================================================================
# Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
# Test Suite: Privileged Traps, Exceptions, and ECALL Handling
# Standard: RISC-V RV32I Assembly
# ==============================================================================

    .section .text
    .globl main
    .type main, @function

main:
    # 1. Install custom trap handler
    la   t0, custom_trap_handler
    csrw mtvec, t0

    # 2. Clear trap recorded flag in s0
    li   s0, 0

    # 3. Trigger ECALL exception
    ecall

    # 4. Check that trap handler was entered and returned cleanly
    li   t1, 1
    bne  s0, t1, fail_trap

    # Test Passed
    li   a0, 0
    ret

fail_trap:
    li   a0, 1
    ret

    .globl custom_trap_handler
    .type custom_trap_handler, @function
custom_trap_handler:
    # Mark trap as visited
    li   s0, 1

    # Verify cause is Machine ECALL (cause = 11)
    csrr t2, mcause
    li   t3, 11
    bne  t2, t3, bad_cause

    # Advance mepc past ecall instruction (4 bytes)
    csrr t4, mepc
    addi t4, t4, 4
    csrw mepc, t4
    mret

bad_cause:
    li   s0, -1
    csrr t4, mepc
    addi t4, t4, 4
    csrw mepc, t4
    mret
