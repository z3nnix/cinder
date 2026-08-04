# Cinder by Example

Cinder is a small systems language with C compatibility, `?T` optionals,
`!T` errors, slices, `defer`, explicit `unsafe`, and an LLVM backend.

This guide teaches Cinder through complete, runnable programs.
Each page shows a program and its output.

## Table of Contents

1. [Hello, World](01_hello_world.md)
2. [Variables](02_variables.md)
3. [Types and Literals](03_types.md)
4. [Functions](04_functions.md)
5. [Control Flow](05_control_flow.md)
6. [Structs](06_structs.md)
7. [Enums](07_enums.md)
8. [Arrays and Slices](08_arrays_slices.md)
9. [Optionals and Errors](09_optionals_errors.md)
10. [defer](10_defer.md)
11. [Compile-Time Code](11_compile_time.md)
12. [Pointers and unsafe](12_pointers_unsafe.md)
13. [Function Pointers](13_function_pointers.md)
14. [Calling C: extern and FFI](14_extern_ffi.md)
15. [Modules](15_modules.md)
16. [The Standard Library](16_stdlib.md)
17. [Bare Metal: Writing a Kernel](17_bare_metal.md)

## Building and Running

The compiler is `./cinder` (a wrapper around `main.rb`).
It needs Ruby and an LLVM toolchain (`llvm-as`, `llc`, `as`, `cc`).

```sh
./cinder check hello.cnd            # parse and type-check only
./cinder build hello.cnd --emit=bin -o hello    # native executable
./hello                              # run it
```

Pass `--mode=release` for optimized builds.

The examples in this guide are checked automatically by `test/docs_test.rb`.
If an example stops compiling, the test suite fails.

## Conventions Used in This Guide

- Every program starts with `use "std/io.cnd";` when it prints.
- `fn main() -> i32` is the entry point; its return value is the exit code.
- Output blocks show the expected result of the preceding program.
- Code fragments (no `fn main`) illustrate one idea and are not runnable alone.
