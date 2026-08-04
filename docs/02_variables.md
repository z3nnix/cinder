# Variables

A `let` binding declares a local variable. Cinder infers the type from the
initializer.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let x = 42;          // i32
    let name = "cinder"; // []u8 (a string)
    let pi = 3.14;       // f64

    println(name);
    print_i32(x);
    print_newline();
    print("pi = ");
    print_u64(pi as u64);
    print_newline();
    return 0;
}
```

```text
$ ./cinder build vars.cnd --emit=bin -o vars
$ ./vars
cinder
42
pi = 3
```

## Type annotations

The type can be written explicitly after a colon.

```cinder
let a: u8 = 200;        // small unsigned integer
let b: i64 = -5;        // large signed integer
let c: usize = 1024;    // pointer-sized unsigned
let s: []u8 = "hi";     // string as a slice of bytes
```

## mut

Bindings are immutable by default. `mut` makes a binding assignable.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let mut counter = 0;
    counter += 1;
    counter += 2;
    print_i32(counter);
    print_newline();

    // let nope = 1;
    // nope = 2;  // error: nope is not mutable
    return 0;
}
```

```text
$ ./vars
3
```

## Shadowing

A new `let` in the same scope shadows the old binding. The old value is
still referenced until the shadowing binding.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let x = 1;
    print_i32(x);
    print(" ");
    let x = x + 10;
    print_i32(x);
    print_newline();
    return 0;
}
```

```text
$ ./shadow
1 11
```

## const

A `const` is a compile-time constant. It must have a value computable at
compile time and cannot be changed.

```cinder
use "std/io.cnd";

const MAX_ITEMS: u32 = 64;
const BLOCK_SIZE = 4096;

fn main() -> i32 {
    print_u32(MAX_ITEMS);
    print_newline();
    print_u32(BLOCK_SIZE);
    print_newline();
    return 0;
}
```

```text
$ ./const
64
4096
```

## static

A `static` is a global variable with a single instance per program.

```cinder
use "std/io.cnd";

static CALLS: u32 = 0;

fn ping() {
    CALLS += 1;
}

fn main() -> i32 {
    ping();
    ping();
    ping();
    print_u32(CALLS);
    print_newline();
    return 0;
}
```

```text
$ ./statics
3
```

## Naming

- Variables and functions use `snake_case`.
- Structs and enums use `PascalCase`.
- Type names may appear in `camelCase` only inside type expressions.
