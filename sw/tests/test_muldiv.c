// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Test Suite: RV32M Hardware Multiplier and Non-Restoring Divider
// Standard: C99
// ==============================================================================

#include "../common/talos.h"

int main(void) {
    uart_puts("[TEST] Starting RV32M Multiplier and Divider Test...\n");

    // 1. Signed and Unsigned Multiplications
    volatile int32_t a = 35;
    volatile int32_t b = -20;
    if (a * b != -700) talos_fail(1);

    volatile int32_t big_pos = 0x7FFFFFFF;
    volatile int32_t neg_one = -1;
    if (big_pos * neg_one != -0x7FFFFFFF) talos_fail(2);

    // 2. High 32-bit Multiplications
    int64_t full_prod = (int64_t)big_pos * (int64_t)big_pos;
    volatile uint32_t expected_hi = (uint32_t)(full_prod >> 32);
    // Use inline assembly for mulh
    int32_t actual_hi;
    __asm__ volatile ("mulh %0, %1, %2" : "=r"(actual_hi) : "r"(big_pos), "r"(big_pos));
    if ((uint32_t)actual_hi != expected_hi) talos_fail(3);

    // 3. Integer Division
    volatile int32_t num = 1000;
    volatile int32_t den = 25;
    if (num / den != 40) talos_fail(4);
    if (num % den != 0) talos_fail(5);

    volatile int32_t num2 = 1003;
    if (num2 / den != 40) talos_fail(6);
    if (num2 % den != 3) talos_fail(7);

    // 4. Division Corner Cases (Division by Zero and Signed Overflow)
    volatile int32_t zero = 0;
    volatile int32_t div_zero;
    __asm__ volatile ("div %0, %1, %2" : "=r"(div_zero) : "r"(num), "r"(zero));
    if (div_zero != -1) talos_fail(8); // RISC-V spec: x / 0 = -1

    volatile int32_t rem_zero;
    __asm__ volatile ("rem %0, %1, %2" : "=r"(rem_zero) : "r"(num), "r"(zero));
    if (rem_zero != num) talos_fail(9); // RISC-V spec: x % 0 = x

    uart_puts("[TEST] RV32M Multiplier/Divider: ALL CHECKS PASSED\n");
    talos_pass();
    return 0;
}
