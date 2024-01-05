# ==============================================================================
# Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
# Test Suite: Deep Register Rename RAW/WAR/WAW Hazard Disambiguation
# Standard: RISC-V RV32IM Assembly
# ==============================================================================

    .section .text
    .globl main
    .type main, @function

main:
    # 1. Independent instructions interleaved with long-latency multicycle operations
    # Mul takes 3 cycles. Independent addis should execute out-of-order ahead of mul!
    li   t0, 15
    li   t1, 4
    mul  t2, t0, t1       # t2 = 60 (3 cycles)

    # Independent instructions (should issue and execute immediately)
    li   t3, 100
    addi t4, t3, 50       # t4 = 150
    addi t5, t4, 25       # t5 = 175

    # Use mul result (RAW hazard)
    add  t6, t2, t5       # t6 = 60 + 175 = 235

    li   a1, 235
    bne  t6, a1, fail_1

    # 2. Write-After-Write (WAW) and Write-After-Read (WAR) renaming test
    # Same architectural register t0 rewritten multiple times
    li   t0, 10
    addi a2, t0, 5        # a2 = 15 (reads t0)
    li   t0, 20           # t0 rewritten (WAR hazard with previous inst, WAW with li)
    addi a3, t0, 5        # a3 = 25 (reads new t0)

    li   a4, 15
    bne  a2, a4, fail_2

    li   a5, 25
    bne  a3, a5, fail_3

    # All dependency chains resolved cleanly
    li   a0, 0
    ret

fail_1:
    li   a0, 1
    ret

fail_2:
    li   a0, 2
    ret

fail_3:
    li   a0, 3
    ret
