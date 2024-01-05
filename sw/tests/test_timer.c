// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Test Suite: 64-bit CLINT Real-Time Timer and Counter Access
// Standard: C99
// ==============================================================================

#include "../common/talos.h"

int main(void) {
    uart_puts("[TEST] Starting CLINT Real-Time Timer Test...\n");

    // Read initial 64-bit timer counter
    uint32_t t_lo0 = mmio_read32(TALOS_CLINT_BASE + CLINT_MTIME_LO);

    // Waste a few cycles in a busy wait loop
    for (volatile int i = 0; i < 100; ++i);

    // Read updated timer counter
    uint32_t t_lo1 = mmio_read32(TALOS_CLINT_BASE + CLINT_MTIME_LO);

    // Verify counter is monotonically incrementing
    if (t_lo1 <= t_lo0) {
        talos_fail(1);
    }

    // Program mtimecmp to a future value
    mmio_write32(TALOS_CLINT_BASE + CLINT_MTIMECMP_LO, t_lo1 + 1000);
    mmio_write32(TALOS_CLINT_BASE + CLINT_MTIMECMP_HI, 0);

    uart_puts("[TEST] CLINT Real-Time Timer: ALL CHECKS PASSED\n");
    talos_pass();
    return 0;
}
