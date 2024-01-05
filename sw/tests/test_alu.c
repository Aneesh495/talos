// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Test Suite: Integer ALU Operations and Edge Cases
// Standard: C99
// ==============================================================================

#include "../common/talos.h"

int main(void) {
    uart_puts("[TEST] Starting Integer ALU Test Suite...\n");

    // 1. Basic Arithmetic
    volatile int32_t a = 12345;
    volatile int32_t b = 67890;
    if (a + b != 80235) talos_fail(1);
    if (b - a != 55545) talos_fail(2);

    // 2. Logical Bitwise Operations
    volatile uint32_t x = 0xAA55AA55;
    volatile uint32_t y = 0x55AA55AA;
    if ((x & y) != 0) talos_fail(3);
    if ((x | y) != 0xFFFFFFFF) talos_fail(4);
    if ((x ^ y) != 0xFFFFFFFF) talos_fail(5);

    // 3. Shifts (Logical and Arithmetic)
    volatile int32_t neg = -64;
    if ((neg >> 2) != -16) talos_fail(6); // Arithmetic shift right
    volatile uint32_t uneg = 0x80000000;
    if ((uneg >> 1) != 0x40000000) talos_fail(7); // Logical shift right
    if ((1 << 16) != 0x00010000) talos_fail(8);

    // 4. Set Less Than (Signed and Unsigned)
    if (a >= b) talos_fail(9);
    if (neg >= a) talos_fail(10);
    if ((uint32_t)neg < (uint32_t)a) talos_fail(11);

    uart_puts("[TEST] Integer ALU Test Suite: ALL CHECKS PASSED\n");
    talos_pass();
    return 0;
}
