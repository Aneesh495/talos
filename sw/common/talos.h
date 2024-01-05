// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Bare-Metal Software Support: System Headers, MMIO, and CSR Definitions
// Standard: C99 / C++17
// ==============================================================================

#ifndef TALOS_H
#define TALOS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Physical Memory Map
#define TALOS_ROM_BASE    0x00010000UL
#define TALOS_ROM_SIZE    0x00010000UL // 64 KB Boot ROM

#define TALOS_CLINT_BASE  0x02000000UL
#define TALOS_CLINT_SIZE  0x00010000UL // 64 KB CLINT

#define TALOS_UART_BASE   0x10000000UL
#define TALOS_UART_SIZE   0x00001000UL // 4 KB UART 16550

#define TALOS_RAM_BASE    0x80000000UL
#define TALOS_RAM_SIZE    0x00010000UL // 64 KB High-Speed BRAM

// TOHOST Communication Address for Verification Pass/Fail
#define TALOS_TOHOST_ADDR 0x80001000UL

// UART 16550 Register Offsets
#define UART_RBR          0x00 // Receiver Buffer Register (Read Only)
#define UART_THR          0x00 // Transmitter Holding Register (Write Only)
#define UART_IER          0x01 // Interrupt Enable Register
#define UART_IIR          0x02 // Interrupt Identification Register
#define UART_FCR          0x02 // FIFO Control Register
#define UART_LCR          0x03 // Line Control Register
#define UART_MCR          0x04 // Modem Control Register
#define UART_LSR          0x05 // Line Status Register
#define UART_MSR          0x06 // Modem Status Register
#define UART_SCR          0x07 // Scratch Register
#define UART_DLL          0x00 // Divisor Latch LSB (when DLAB = 1)
#define UART_DLM          0x01 // Divisor Latch MSB (when DLAB = 1)

#define UART_LSR_DR       0x01 // Data Ready
#define UART_LSR_THRE     0x20 // Transmitter Holding Register Empty
#define UART_LSR_TEMT     0x40 // Transmitter Empty

// CLINT Register Offsets
#define CLINT_MSIP        0x0000 // Machine Software Interrupt Pending
#define CLINT_MTIMECMP_LO 0x4000 // Machine Timer Compare Low Word
#define CLINT_MTIMECMP_HI 0x4004 // Machine Timer Compare High Word
#define CLINT_MTIME_LO    0xBFF8 // Machine Real-Time Counter Low Word
#define CLINT_MTIME_HI    0xBFFC // Machine Real-Time Counter High Word

// Privileged Architecture CSR Access Macros
#define read_csr(reg) ({ \
    unsigned long __tmp; \
    __asm__ volatile ("csrr %0, " #reg : "=r"(__tmp)); \
    __tmp; })

#define write_csr(reg, val) ({ \
    __asm__ volatile ("csrw " #reg ", %0" :: "rK"(val)); })

#define set_csr(reg, bit) ({ \
    unsigned long __tmp; \
    __asm__ volatile ("csrrs %0, " #reg ", %1" : "=r"(__tmp) : "rK"(bit)); \
    __tmp; })

#define clear_csr(reg, bit) ({ \
    unsigned long __tmp; \
    __asm__ volatile ("csrrc %0, " #reg ", %1" : "=r"(__tmp) : "rK"(bit)); \
    __tmp; })

// Memory-Mapped IO Access Helpers
static inline uint8_t mmio_read8(uintptr_t addr) {
    return *(volatile uint8_t*)addr;
}

static inline void mmio_write8(uintptr_t addr, uint8_t val) {
    *(volatile uint8_t*)addr = val;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
    return *(volatile uint32_t*)addr;
}

static inline void mmio_write32(uintptr_t addr, uint32_t val) {
    *(volatile uint32_t*)addr = val;
}

static inline uint64_t mmio_read64(uintptr_t addr) {
    return *(volatile uint64_t*)addr;
}

static inline void mmio_write64(uintptr_t addr, uint64_t val) {
    *(volatile uint64_t*)addr = val;
}

// Low-Level UART Driver Functions
static inline void uart_putc(char c) {
    while ((mmio_read8(TALOS_UART_BASE + UART_LSR) & UART_LSR_THRE) == 0);
    mmio_write8(TALOS_UART_BASE + UART_THR, (uint8_t)c);
}

static inline void uart_puts(const char* s) {
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

static inline void uart_puthex(uint32_t val) {
    const char hex_chars[] = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 7; i >= 0; --i) {
        uart_putc(hex_chars[(val >> (i * 4)) & 0xF]);
    }
}

static inline void uart_putdec(uint32_t val) {
    if (val == 0) {
        uart_putc('0');
        return;
    }
    char buf[12];
    int idx = 0;
    while (val > 0) {
        buf[idx++] = '0' + (val % 10);
        val /= 10;
    }
    for (int i = idx - 1; i >= 0; --i) {
        uart_putc(buf[i]);
    }
}

// Performance Counter Querying
static inline uint64_t talos_cycles(void) {
    uint32_t hi0, hi1, lo;
    do {
        hi0 = read_csr(mcycleh);
        lo  = read_csr(mcycle);
        hi1 = read_csr(mcycleh);
    } while (hi0 != hi1);
    return ((uint64_t)hi0 << 32) | lo;
}

static inline uint64_t talos_instret(void) {
    uint32_t hi0, hi1, lo;
    do {
        hi0 = read_csr(minstreth);
        lo  = read_csr(minstret);
        hi1 = read_csr(minstreth);
    } while (hi0 != hi1);
    return ((uint64_t)hi0 << 32) | lo;
}

// Verification Harness Signaling
static inline void talos_pass(void) {
    uart_puts("\n[TALOS] Verification Status: SUCCESS\n");
    mmio_write32(TALOS_TOHOST_ADDR, 1);
    while (1) {
        __asm__ volatile ("wfi");
    }
}

static inline void talos_fail(uint32_t code) {
    uart_puts("\n[TALOS] Verification Status: FAILED (Code: ");
    uart_puthex(code);
    uart_puts(")\n");
    mmio_write32(TALOS_TOHOST_ADDR, (code << 1) | 1);
    while (1) {
        __asm__ volatile ("wfi");
    }
}

#ifdef __cplusplus
}
#endif

#endif // TALOS_H
