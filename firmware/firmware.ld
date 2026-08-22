/*
 * firmware.ld  –  Linker script for the main application firmware
 *
 * The bootloader copies firmware.bin from SD card to App BRAM starting
 * at 0x0001_0000, then jumps there.  All application code must be
 * position-dependent and linked to start at 0x0001_0000.
 *
 * App BRAM: 20 KB at 0x0001_0000 – 0x0001_4FFF
 * Stack: top of App BRAM (0x0001_5000), grows downward 4 KB reserved.
 */

MEMORY
{
    APP_RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 20K
}

ENTRY(app_entry)

SECTIONS
{
    . = 0x00010000;

    /* ---- Reset / entry vector ---- */
    .text.entry : {
        *(.text.entry)
    } > APP_RAM

    /* ---- Code ---- */
    .text : {
        *(.text*)
    } > APP_RAM

    /* ---- Read-only data ---- */
    .rodata : {
        *(.rodata*)
    } > APP_RAM

    /* ---- Initialised data ---- */
    .data : {
        *(.data*)
    } > APP_RAM

    /* ---- Zero-initialised data ---- */
    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > APP_RAM

    _stack_top = ORIGIN(APP_RAM) + LENGTH(APP_RAM);

    ASSERT(. <= _stack_top - 0x1000,
        "ERROR: application too large – does not fit in 20 KB App BRAM!")
}
