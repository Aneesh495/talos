// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Test Suite: Memory-Mapped UART 16550 Serial Line Interface
// Standard: C99
// ==============================================================================

#include "../common/talos.h"

int main(void) {
    uart_puts("[TEST] Starting Memory-Mapped UART 16550 Test...\n");

    // 1. Verify Line Status Register reflects ready state
    uint8_t lsr = mmio_read8(TALOS_UART_BASE + UART_LSR);
    if ((lsr & UART_LSR_THRE) == 0) {
        talos_fail(1);
    }

    // 2. Transmit test string character-by-character
    const char msg[] = "TALOS_UART_OK\n";
    for (int i = 0; msg[i] != '\0'; ++i) {
        uart_putc(msg[i]);
    }

    // 3. Print hex and decimal conversions
    uart_puts("Numeric format test: ");
    uart_puthex(0xDEADBEEF);
    uart_puts(" = ");
    uart_putdec(123456789);
    uart_puts("\n");

    uart_puts("[TEST] Memory-Mapped UART: ALL CHECKS PASSED\n");
    talos_pass();
    return 0;
}
