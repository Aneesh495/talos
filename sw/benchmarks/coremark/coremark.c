// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Benchmark: EEMBC CoreMark Bare-Metal Workload Harness
// Standard: C99
// ==============================================================================

#include "../../common/talos.h"

#define COREMARK_ITERATIONS 200

// Matrix operation kernel
static int matrix_test(int N, int *val) {
    int A[8][8], B[8][8], C[8][8];
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) {
            A[i][j] = (i + j) * (*val);
            B[i][j] = (i - j) + (*val);
            C[i][j] = 0;
        }
    }
    for (int i = 0; i < N; ++i) {
        for (int k = 0; k < N; ++k) {
            for (int j = 0; j < N; ++j) {
                C[i][j] += A[i][k] * B[k][j];
            }
        }
    }
    int crc = 0;
    for (int i = 0; i < N; ++i) {
        crc += C[i][i];
    }
    return crc;
}

// Linked list traversal kernel
typedef struct list_node {
    struct list_node *next;
    int data;
} list_node_t;

static int list_test(int num_nodes) {
    list_node_t nodes[16];
    for (int i = 0; i < num_nodes - 1; ++i) {
        nodes[i].next = &nodes[i + 1];
        nodes[i].data = i * 7 + 3;
    }
    nodes[num_nodes - 1].next = 0;
    nodes[num_nodes - 1].data = 99;

    int sum = 0;
    list_node_t *cur = &nodes[0];
    while (cur) {
        sum += cur->data;
        cur = cur->next;
    }
    return sum;
}

// State machine kernel
static int state_test(int input) {
    int state = 0;
    for (int i = 0; i < 32; ++i) {
        int bit = (input >> i) & 1;
        switch (state) {
            case 0: state = bit ? 1 : 2; break;
            case 1: state = bit ? 0 : 3; break;
            case 2: state = bit ? 3 : 1; break;
            case 3: state = bit ? 2 : 0; break;
        }
    }
    return state;
}

int main(void) {
    uart_puts("[BENCHMARK] Starting CoreMark Workload Harness (200 iterations)...\n");

    uint64_t start_cycles = talos_cycles();
    uint64_t start_insts  = talos_instret();

    int total_crc = 0;
    int val = 3;

    for (int iter = 0; iter < COREMARK_ITERATIONS; ++iter) {
        total_crc += matrix_test(6, &val);
        total_crc += list_test(16);
        total_crc += state_test(total_crc ^ iter);
        val = (val * 1103515245 + 12345) & 0x7FFFFFFF;
    }

    uint64_t end_cycles = talos_cycles();
    uint64_t end_insts  = talos_instret();

    if (total_crc == 0) {
        uart_puts("[BENCHMARK] CoreMark Verification: FAILED\n");
        talos_fail(1);
    }

    uint64_t elapsed_cycles = end_cycles - start_cycles;
    uint64_t elapsed_insts  = end_insts - start_insts;

    uart_puts("[BENCHMARK] CoreMark 200 iterations completed in ");
    uart_putdec((uint32_t)elapsed_cycles);
    uart_puts(" cycles, ");
    uart_putdec((uint32_t)elapsed_insts);
    uart_puts(" instructions.\n");

    talos_pass();
    return 0;
}
