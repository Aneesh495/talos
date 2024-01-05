// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Test Suite: Concurrent Non-Blocking L1 Data Cache MSHR Stress Test
// Standard: C99
// ==============================================================================

#include "../common/talos.h"

#define STRIDE 1024 // Different cache lines across 8KB 4-way cache
static volatile uint32_t test_array[4096];

int main(void) {
    uart_puts("[TEST] Starting Non-Blocking D-Cache MSHR Stress Test...\n");

    // Initialize array at strided locations
    test_array[0 * STRIDE] = 0x11111111;
    test_array[1 * STRIDE] = 0x22222222;
    test_array[2 * STRIDE] = 0x33333333;
    test_array[3 * STRIDE] = 0x44444444;

    // Issue 4 back-to-back strided loads to trigger 4 concurrent misses (allocating all 4 MSHR slots)
    volatile uint32_t val0 = test_array[0 * STRIDE];
    volatile uint32_t val1 = test_array[1 * STRIDE];
    volatile uint32_t val2 = test_array[2 * STRIDE];
    volatile uint32_t val3 = test_array[3 * STRIDE];

    // Verify all returned values
    if (val0 != 0x11111111) talos_fail(1);
    if (val1 != 0x22222222) talos_fail(2);
    if (val2 != 0x33333333) talos_fail(3);
    if (val3 != 0x44444444) talos_fail(4);

    uart_puts("[TEST] Non-Blocking D-Cache MSHR: ALL CHECKS PASSED\n");
    talos_pass();
    return 0;
}
