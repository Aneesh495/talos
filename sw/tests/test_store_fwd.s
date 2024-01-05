# ==============================================================================
# Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
# Test Suite: Speculative Store-to-Load Byte-Level Forwarding
# Standard: RISC-V RV32I Assembly
# ==============================================================================

    .section .text
    .globl main
    .type main, @function

main:
    # Use stack space for memory test
    addi sp, sp, -32

    # 1. Direct Word Store-to-Load Forwarding
    li   t0, 0x12345678
    sw   t0, 0(sp)
    lw   t1, 0(sp)        # Load should forward directly from store queue!
    bne  t0, t1, fail_fwd_word

    # 2. Byte Store and Byte Load Forwarding
    li   t2, 0x5A
    sb   t2, 4(sp)
    lbu  t3, 4(sp)
    bne  t2, t3, fail_fwd_byte

    # 3. Halfword Store and Halfword Load Forwarding
    li   t4, 0x3C9A
    sh   t4, 6(sp)
    lhu  t5, 6(sp)
    bne  t4, t5, fail_fwd_half

    # 4. Multi-byte Store merge: Write two halfwords, load one full word
    li   t6, 0xAAAA
    sh   t6, 8(sp)
    li   a1, 0x5555
    sh   a1, 10(sp)
    lw   a2, 8(sp)
    li   a3, 0x5555AAAA
    bne  a2, a3, fail_fwd_merge

    # Pass
    addi sp, sp, 32
    li   a0, 0
    ret

fail_fwd_word:
    addi sp, sp, 32
    li   a0, 1
    ret

fail_fwd_byte:
    addi sp, sp, 32
    li   a0, 2
    ret

fail_fwd_half:
    addi sp, sp, 32
    li   a0, 3
    ret

fail_fwd_merge:
    addi sp, sp, 32
    li   a0, 4
    ret
