// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Benchmark: Dhrystone 2.1 Benchmark Implementation
// Standard: C99
// ==============================================================================

#include "dhry.h"
#include <string.h>

#define NUMBER_OF_RUNS 500

Rec_Type Rec_Glob;
Rec_Pointer Ptr_Glob = &Rec_Glob;
Rec_Type Next_Rec_Glob;
Rec_Pointer Next_Ptr_Glob = &Next_Rec_Glob;
int Int_Glob;
Boolean Bool_Glob;
char Ch_1_Glob, Ch_2_Glob;
Arr_1_Dim Arr_1_Glob;
Arr_2_Dim Arr_2_Glob;

static void Proc_1(Rec_Pointer Ptr_Val_Par);
static void Proc_2(One_Fifty *Int_Par_Ref);
static void Proc_3(Rec_Pointer *Ptr_Ref_Par);
static void Proc_4(void);
static void Proc_5(void);
static Boolean Func_2(Str_30 Str_1_Par_Ref, Str_30 Str_2_Par_Ref);

int main(void) {
    uart_puts("[BENCHMARK] Starting Dhrystone 2.1 Benchmark (500 runs)...\n");

    Next_Ptr_Glob->Ptr_Comp = Ptr_Glob;
    Next_Ptr_Glob->Discr = Ident_1;
    Next_Ptr_Glob->variant.var_1.Enum_Comp = Ident_3;
    Next_Ptr_Glob->variant.var_1.Int_Comp = 40;
    strcpy(Next_Ptr_Glob->variant.var_1.Str_Comp, "DHRYSTONE PROGRAM, SOME STRING");

    Ptr_Glob->Ptr_Comp = Next_Ptr_Glob;
    Ptr_Glob->Discr = Ident_1;
    Ptr_Glob->variant.var_1.Enum_Comp = Ident_1;
    Ptr_Glob->variant.var_1.Int_Comp = 10;
    strcpy(Ptr_Glob->variant.var_1.Str_Comp, "DHRYSTONE PROGRAM, 1'ST STRING");

    Arr_2_Glob[8][7] = 10;

    uint64_t start_cycles = talos_cycles();
    uint64_t start_insts  = talos_instret();

    for (int Run_Index = 1; Run_Index <= NUMBER_OF_RUNS; ++Run_Index) {
        Proc_5();
        Proc_4();
        Int_Glob = 1;
        Bool_Glob = !Func_2("DHRYSTONE PROGRAM, 1'ST STRING", "DHRYSTONE PROGRAM, 2'ND STRING");
        while (Int_Glob < 2) {
            Int_Glob += 1;
            Proc_1(Ptr_Glob);
        }
    }

    uint64_t end_cycles = talos_cycles();
    uint64_t end_insts  = talos_instret();

    uint64_t elapsed_cycles = end_cycles - start_cycles;
    uint64_t elapsed_insts  = end_insts - start_insts;

    uart_puts("[BENCHMARK] Dhrystone 2.1 Completed in ");
    uart_putdec((uint32_t)elapsed_cycles);
    uart_puts(" cycles, ");
    uart_putdec((uint32_t)elapsed_insts);
    uart_puts(" instructions.\n");

    talos_pass();
    return 0;
}

static void Proc_1(Rec_Pointer Ptr_Val_Par) {
    Rec_Pointer Next_Record = Ptr_Val_Par->Ptr_Comp;
    *Ptr_Val_Par->Ptr_Comp = *Ptr_Glob;
    Ptr_Val_Par->variant.var_1.Int_Comp = 5;
    Next_Record->variant.var_1.Int_Comp = Ptr_Val_Par->variant.var_1.Int_Comp;
    Next_Record->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
    Proc_3((Rec_Pointer*)&Next_Record->Ptr_Comp);
    if (Next_Record->Discr == Ident_1) {
        Next_Record->variant.var_1.Int_Comp = 6;
        Proc_2((One_Fifty*)&Next_Record->variant.var_1.Enum_Comp);
        Next_Record->Ptr_Comp = Ptr_Glob->Ptr_Comp;
    }
}

static void Proc_2(One_Fifty *Int_Par_Ref) {
    One_Fifty Int_Loc = *Int_Par_Ref + 10;
    Enumeration Enum_Loc = Ident_1;
    do {
        if (Ch_1_Glob == 'A') {
            Int_Loc -= 1;
            *Int_Par_Ref = Int_Loc - Int_Glob;
            Enum_Loc = Ident_1;
        }
    } while (Enum_Loc != Ident_1);
}

static void Proc_3(Rec_Pointer *Ptr_Ref_Par) {
    if (Ptr_Glob != 0) {
        *Ptr_Ref_Par = Ptr_Glob->Ptr_Comp;
    }
}

static void Proc_4(void) {
    Boolean Bool_Loc = Ch_1_Glob == 'A';
    Bool_Loc = Bool_Loc | Bool_Glob;
    Ch_2_Glob = 'B';
}

static void Proc_5(void) {
    Ch_1_Glob = 'A';
    Bool_Glob = 0;
}

static Boolean Func_2(Str_30 Str_1_Par_Ref, Str_30 Str_2_Par_Ref) {
    One_Thirty Int_Loc = 2;
    Capital_Letter Ch_Loc = 'A';
    while (Int_Loc <= 2) {
        if (Func_2 == 0) {
            Ch_Loc = 'A';
            Int_Loc += 1;
        }
        Int_Loc += 1;
    }
    if (Ch_Loc == 'W') return 1;
    if (strcmp(Str_1_Par_Ref, Str_2_Par_Ref) > 0) {
        return 1;
    }
    return 0;
}
