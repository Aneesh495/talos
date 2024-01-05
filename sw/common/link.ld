/* ==============================================================================
 * Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
 * GNU Linker Script: Memory Map and Section Allocation for Bare-Metal Runtime
 * Standard: GNU ld
 * ============================================================================== */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
    /* Entrypoint and early hardware initialization placed at base of RAM */
    .text.init :
    {
        *(.text.init)
    } > RAM

    .text :
    {
        *(.text .text.*)
        *(.gnu.linkonce.t.*)
    } > RAM

    .rodata :
    {
        *(.rdata)
        *(.rodata .rodata.*)
        *(.gnu.linkonce.r.*)
        . = ALIGN(4);
    } > RAM

    .data :
    {
        *(.data .data.*)
        *(.gnu.linkonce.d.*)
        . = ALIGN(4);
    } > RAM

    .sdata :
    {
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
        *(.gnu.linkonce.s.*)
        . = ALIGN(4);
    } > RAM

    .sbss :
    {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.gnu.linkonce.sb.*)
        *(.scommon)
        . = ALIGN(4);
    } > RAM

    .bss :
    {
        *(.bss .bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /* End of allocated image */
    _end = .;
    PROVIDE(end = .);

    /* Hardware stack placed at top of 64KB on-chip RAM */
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
