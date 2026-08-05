.set MB_MAGIC,   0x1BADB002
.set MB_FLAGS,   0x0
.set MB_CHECKSUM, -(MB_MAGIC + MB_FLAGS)

.section .multiboot, "a"
.align 4
.long MB_MAGIC
.long MB_FLAGS
.long MB_CHECKSUM

.section .boot, "ax"
.code32

.global _start
.type _start, @function
_start:
    cli

    movl $boot_stack_top, %esp

    lgdt (gdt_desc)

    movl %cr4, %eax
    orl  $0x20, %eax
    movl %eax, %cr4

    movl $pml4, %eax
    movl %eax, %cr3

    movl $0xC0000080, %ecx
    rdmsr
    orl  $0x100, %eax
    wrmsr

    movl %cr0, %eax
    orl  $0x80000001, %eax
    movl %eax, %cr0

    ljmp $0x08, $start64

.code64
start64:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    movabs $boot_stack_top, %rsp
    call cinder_kmain
    cli
    hlt
    jmp start64
.size _start, . - _start

.section .boot
.align 8
gdt:
    .quad 0x0000000000000000
    .quad 0x00AF9A000000FFFF
    .quad 0x00CF92000000FFFF
gdt_desc:
    .word gdt_desc - gdt - 1
    .long gdt

.align 4096
pml4:
    .quad (pdpt + 0x3)
    .rept 511
    .quad 0x0
    .endr

.align 4096
pdpt:
    .quad (pd + 0x3)
    .rept 511
    .quad 0x0
    .endr

.align 4096
pd:
    .set i, 0
    .rept 512
    .quad (i * 0x200000) | 0x83
    .set i, i + 1
    .endr