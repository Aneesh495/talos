# ==============================================================================
# Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
# Test Suite: Branch Predictor, RAS, and Misprediction Recovery Test
# Standard: RISC-V RV32I Assembly
# ==============================================================================

    .section .text
    .globl main
    .type main, @function

main:
    # 1. Forward conditional branch taken
    li   t0, 10
    li   t1, 10
    beq  t0, t1, br_taken_1
    li   a0, 1
    ret

br_taken_1:
    # 2. Forward conditional branch not taken
    bne  t0, t1, br_fail_2
    j    br_test_3

br_fail_2:
    li   a0, 2
    ret

br_test_3:
    # 3. Backward loop branch (tests Gshare branch history shift and BTB hit)
    li   t2, 0       # loop counter
    li   t3, 100     # bound
loop_start:
    addi t2, t2, 1
    blt  t2, t3, loop_start

    # Verify loop counter reached exactly 100
    bne  t2, t3, loop_fail
    j    ras_test

loop_fail:
    li   a0, 3
    ret

ras_test:
    # 4. Return Address Stack (RAS) Call and Return chain
    jal  ra, func_a
    # If return succeeds, test passed
    li   a0, 0
    ret

func_a:
    addi sp, sp, -16
    sw   ra, 12(sp)
    jal  ra, func_b
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

func_b:
    addi sp, sp, -16
    sw   ra, 12(sp)
    jal  ra, func_c
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

func_c:
    # Leaf function returning directly
    ret
