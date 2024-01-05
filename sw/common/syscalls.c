// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Bare-Metal Software Support: C Runtime Minimal System Call Stubs
// Standard: C99 / POSIX.1
// ==============================================================================

#include "talos.h"
#include <sys/stat.h>
#include <errno.h>

#undef errno
extern int errno;

void _exit(int status) {
    if (status == 0) {
        talos_pass();
    } else {
        talos_fail(status);
    }
    while (1);
}

int _write(int file, char *ptr, int len) {
    (void)file;
    for (int i = 0; i < len; ++i) {
        uart_putc(ptr[i]);
    }
    return len;
}

int _close(int file) {
    (void)file;
    return -1;
}

int _fstat(int file, struct stat *st) {
    (void)file;
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int file) {
    (void)file;
    return 1;
}

int _lseek(int file, int ptr, int dir) {
    (void)file;
    (void)ptr;
    (void)dir;
    return 0;
}

int _read(int file, char *ptr, int len) {
    (void)file;
    (void)ptr;
    (void)len;
    return 0;
}

caddr_t _sbrk(int incr) {
    extern char end; // Symbol provided by linker script
    static char *heap_end = 0;
    char *prev_heap_end;

    if (heap_end == 0) {
        heap_end = &end;
    }

    prev_heap_end = heap_end;
    heap_end += incr;

    return (caddr_t)prev_heap_end;
}
