# The Cinder Programming Language

<img align="left" src="meta/logo.png" width="124" alt="Kyronix logo">

So, for a long time of overthinking I finally realized things that I hate in C and... I wanna try fix them.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let greetings = [
        "Hello world",
        "Привет, мир!",
        "¡Hola Mundo!",
        "Привіт, світе!",
        "السلام عليكم!"
        ];

    for value in greetings {
        println(value);
    }
    return 0;
}
```

## Features
- Minimalism
- Explicitness
- C compatibility
- Bare metal
- Fast compilation
- LLVM backend

## Get started
First, you need install the compiler:
```bash
curl https://raw.githubusercontent.com/z3nnix/cinder/refs/heads/main/scripts/install.sh | sudo bash
```
_script location is [scripts/install.sh](https://github.com/z3nnix/cinder/blob/main/scripts/install.sh)_
Next, visit [Cinder by example](https://z3nnix.github.io/cinder) and learn Cinder step by step :)

## Documentation

The [docs/](docs/) directory contains **Cinder by Example**, a set of short,
self-contained programs with expected output. Every example is verified
automatically (see `test/docs_test.rb`).

| Chapter | Topic |
|---------|-------|
| [Hello World](docs/01_hello_world.md) | running, return codes |
| [Variables](docs/02_variables.md) | let, mut, const, static |
| [Types](docs/03_types.md) | integers, floats, bool, char, strings |
| [Functions](docs/04_functions.md) | definition, void, early return, unsafe fn |
| [Control Flow](docs/05_control_flow.md) | if, loop, while, for, switch |
| [Structs](docs/06_structs.md) | fields, methods, sizeof/offsetof |
| [Enums](docs/07_enums.md) | variants, shorthand, switch |
| [Arrays and Slices](docs/08_arrays_slices.md) | literals, ranges, slicing |
| [Optionals and Errors](docs/09_optionals_errors.md) | ?T, !T, else, ?, unwrap |
| [defer](docs/10_defer.md) | deferred cleanup, LIFO order |
| [Compile-Time Code](docs/11_compile_time.md) | const, static_assert, sizeof |
| [Pointers and Unsafe](docs/12_pointers_unsafe.md) | *, &null, *void, asm |
| [Function Pointers](docs/13_function_pointers.md) | fn types, callbacks |
| [FFI](docs/14_ffi.md) | extern fn, c-strings, varargs |
| [Modules](docs/15_modules.md) | use, export, target filter |
| [Standard Library](docs/16_stdlib.md) | io, vec, string, str, math, alloc |
| [Bare Metal](docs/17_bare_metal.md) | kernel build, x86.cnd, uart |

## License
See the file [LICENSE](LICENSE).

## Contributing
Just send pull-request! Any helpful PR are welcome :3
