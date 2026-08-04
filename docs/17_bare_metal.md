# Bare Metal

`--emit=kernel` builds a freestanding ELF with no libc. The standard library
splits into hosted modules (`io`, `vec`, `alloc`, ...) and a bare-metal
module (`std/x86.cnd`) for port I/O.

## Minimal kernel

The file `examples/kernel/` contains a working QEMU test:

`boot.s` - multiboot entry, sets up a stack, then jumps to `kernel_main`:

```gas
# examples/kernel/boot.s
.section .multiboot
.align 4
.long 0x1badb002
.long 0
.long -(0x1badb002)

.section .text
.global _start
_start:
    movl $stack_top, %esp
    call kernel_main
hang:
    hlt
    jmp hang

.section .bss
.align 16
stack_bottom:
    .skip 4096
stack_top:
```

`linker.ld` - 1 MiB base, kernel at 1 MiB:

```ld
ENTRY(_start)
SECTIONS {
    . = 1M;
    .text : { *(.multiboot) *(.text) }
    .bss  : { *(.bss) }
}
```

`main.cnd`:

```cinder
use "std/x86.cnd";

unsafe fn uart_init() {
    outb(0x3F9, 0x00);
    outb(0x3FB, 0x80);
    outb(0x3F8, 0x03);
    outb(0x3F9, 0x00);
    outb(0x3FB, 0x03);
}

unsafe fn uart_write_byte(b: u8) {
    while (inb(0x3FD) & 0x20) == 0 {
        asm("nop");
    }
    outb(0x3F8, b);
}

unsafe fn uart_write_str(s: []u8) {
    for i in 0 .. s.len {
        uart_write_byte(s[i]);
    }
}

export fn kernel_main() {
    unsafe {
        uart_init();
        uart_write_str("Hello world!\n");
        loop {
            asm("hlt");
        }
    }
}
```

## Build and run

```bash
ruby main.rb build main.cnd --emit=kernel \
    --boot=boot.s \
    --linker-script=linker.ld \
    -o kernel
qemu-system-i386 -nographic -kernel kernel
```

`--boot` links a raw assembly entry point; `--linker-script` places the
binary. `kernel_main` must be exported because the boot stub calls it by
name.

## What works on bare metal

- `outb` / `outw` / `outl` / `inb` / `inw` / `inl` - `std/x86.cnd`
- `asm("...")` - inline assembly in `unsafe` blocks
- All scalar types, structs, enums, arrays, slices, and function pointers
- `const`, `static`, and compile-time operators
- No `io` prints, no `alloc`, no `vec` / `string` (these need libc)

The `#[target("x86_64-freestanding")]` attribute restricts a declaration to
the freestanding target:

```cinder
#[target("x86_64-freestanding")]
fn uart_putc(c: u8) {
    unsafe { outb(0x3F8, c); }
}
```
