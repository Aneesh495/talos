// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Test Suite: RV32F IEEE-754 Single-Precision Floating-Point Operations
// Standard: C99
// ==============================================================================

#include "../common/talos.h"

int main(void) {
    uart_puts("[TEST] Starting IEEE-754 Single-Precision FPU Test...\n");

    // 1. Basic Single Precision Addition and Subtraction
    volatile float f1 = 1.5f;
    volatile float f2 = 2.25f;
    volatile float f_add = f1 + f2;
    if (f_add != 3.75f) talos_fail(1);

    volatile float f_sub = f2 - f1;
    if (f_sub != 0.75f) talos_fail(2);

    // 2. Multiplication
    volatile float f_mul = f1 * f2;
    if (f_mul != 3.375f) talos_fail(3);

    // 3. Integer to Float and Float to Integer Conversion
    volatile int32_t ival = 42;
    volatile float f_from_i = (float)ival;
    if (f_from_i != 42.0f) talos_fail(4);

    volatile int32_t i_from_f = (int32_t)f_add;
    if (i_from_f != 3) talos_fail(5);

    // 4. Floating Point Comparison
    if (f1 >= f2) talos_fail(6);
    if (f2 <= f1) talos_fail(7);
    if (f1 != 1.5f) talos_fail(8);

    uart_puts("[TEST] IEEE-754 FPU: ALL CHECKS PASSED\n");
    talos_pass();
    return 0;
}
