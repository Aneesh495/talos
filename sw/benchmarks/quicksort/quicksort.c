// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Benchmark: In-Place Randomized Quicksort (1024 Elements)
// Standard: C99
// ==============================================================================

#include "../../common/talos.h"

#define NUM_ELEMENTS 1024
static int32_t data[NUM_ELEMENTS];

// Simple linear congruential pseudorandom generator
static uint32_t lcg_state = 123456789;
static uint32_t rand_lcg(void) {
    lcg_state = lcg_state * 1664525 + 1013904223;
    return lcg_state;
}

static void swap(int32_t *a, int32_t *b) {
    int32_t t = *a;
    *a = *b;
    *b = t;
}

static int partition(int32_t arr[], int low, int high) {
    int32_t pivot = arr[high];
    int i = (low - 1);

    for (int j = low; j <= high - 1; j++) {
        if (arr[j] < pivot) {
            i++;
            swap(&arr[i], &arr[j]);
        }
    }
    swap(&arr[i + 1], &arr[high]);
    return (i + 1);
}

static void quicksort(int32_t arr[], int low, int high) {
    if (low < high) {
        int pi = partition(arr, low, high);
        quicksort(arr, low, pi - 1);
        quicksort(arr, pi + 1, high);
    }
}

int main(void) {
    uart_puts("[BENCHMARK] Starting In-Place Quicksort (1024 integers)...\n");

    // Populate data with pseudorandom integers
    for (int i = 0; i < NUM_ELEMENTS; ++i) {
        data[i] = (int32_t)(rand_lcg() % 100000);
    }

    uint64_t start_cycles = talos_cycles();
    uint64_t start_insts  = talos_instret();

    quicksort(data, 0, NUM_ELEMENTS - 1);

    uint64_t end_cycles = talos_cycles();
    uint64_t end_insts  = talos_instret();

    // Verify sorted order
    for (int i = 0; i < NUM_ELEMENTS - 1; ++i) {
        if (data[i] > data[i + 1]) {
            uart_puts("[BENCHMARK] Quicksort Verification: FAILED\n");
            talos_fail(1);
        }
    }

    uint64_t elapsed_cycles = end_cycles - start_cycles;
    uint64_t elapsed_insts  = end_insts - start_insts;

    uart_puts("[BENCHMARK] Quicksort Sorted 1024 elements in ");
    uart_putdec((uint32_t)elapsed_cycles);
    uart_puts(" cycles, ");
    uart_putdec((uint32_t)elapsed_insts);
    uart_puts(" instructions.\n");

    talos_pass();
    return 0;
}
