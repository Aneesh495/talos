// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Benchmark: Floating-Point General Matrix Multiplication (GEMM 32x32)
// Standard: C99
// ==============================================================================

#include "../../common/talos.h"

#define N 32
static float A[N][N];
static float B[N][N];
static float C[N][N];

static void init_matrices(void) {
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) {
            A[i][j] = (float)((i + j) % 10) * 0.1f;
            B[i][j] = (float)((i * j) % 10) * 0.1f;
            C[i][j] = 0.0f;
        }
    }
}

static void gemm(void) {
    for (int i = 0; i < N; ++i) {
        for (int k = 0; k < N; ++k) {
            float r_a = A[i][k];
            for (int j = 0; j < N; ++j) {
                C[i][j] += r_a * B[k][j];
            }
        }
    }
}

int main(void) {
    uart_puts("[BENCHMARK] Starting GEMM 32x32 Floating-Point Matrix Multiply...\n");

    init_matrices();

    uint64_t start_cycles = talos_cycles();
    uint64_t start_insts  = talos_instret();

    gemm();

    uint64_t end_cycles = talos_cycles();
    uint64_t end_insts  = talos_instret();

    // Verify non-zero output
    float sum = 0.0f;
    for (int i = 0; i < N; ++i) {
        sum += C[i][i];
    }

    if (sum <= 0.0f) {
        uart_puts("[BENCHMARK] GEMM Verification: FAILED\n");
        talos_fail(1);
    }

    uint64_t elapsed_cycles = end_cycles - start_cycles;
    uint64_t elapsed_insts  = end_insts - start_insts;

    uart_puts("[BENCHMARK] GEMM completed in ");
    uart_putdec((uint32_t)elapsed_cycles);
    uart_puts(" cycles, ");
    uart_putdec((uint32_t)elapsed_insts);
    uart_puts(" instructions.\n");

    talos_pass();
    return 0;
}
