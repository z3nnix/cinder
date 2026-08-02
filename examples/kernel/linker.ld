OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SECTIONS {
    . = 1M;

    .multiboot : {
        KEEP(*(.multiboot))
    }

    .boot : {
        *(.boot)
    }

    .text : {
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
    }

    .bss : {
        *(.bss*)
        *(COMMON)
    }

    . = ALIGN(16);
    boot_stack_bottom = .;
    . += 16384;
    boot_stack_top = .;
}
