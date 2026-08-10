# Variables

A `let` binding declares a local variable. Cinder infers the type from the
initializer.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let x = 42;          // i32
    let name = "cinder"; // []u8 (a string)
    let pi = 3.14;       // f64

    print(&x, .I32);
    putchar(10);

    println(name);

    print(&pi, .F64);

    return 0;
}
```

```text
$ ./cinder build vars.cnd --emit=bin -o vars
$ ./vars
42
cinder
3.14
```

## Type annotations

The type can be written explicitly after a colon.

```rust
let a: u8 = 200;        // small unsigned integer
let b: i64 = -5;        // large signed integer
let c: usize = 1024;    // pointer-sized unsigned
let s: []u8 = "hi";     // string as a slice of bytes
```

## mut

Bindings are immutable by default. `mut` makes a binding assignable.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let mut counter = 0;
    counter += 1;
    counter += 2;

    print(&counter, .I32);
    putchar(10);

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

```rust
use "std/io.cnd";

fn main() -> i32 {
    let x = 1;
    print(&x, .I32);

    let sp: []u8 = " ";
    print(&sp, .S);

    let x = x + 10;
    print(&x, .I32);
    putchar(10);

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

```rust
use "std/io.cnd";

const MAX_ITEMS: u32 = 64;
const BLOCK_SIZE = 4096;

fn main() -> i32 {
    let max_items: i32 = MAX_ITEMS as i32;
    print(&max_items, .I32);
    putchar(10);

    let block_size: i32 = BLOCK_SIZE;
    print(&block_size, .I32);
    putchar(10);

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

```rust
use "std/io.cnd";

static CALLS: u32 = 0;

fn ping() {
    CALLS += 1;
}

fn main() -> i32 {
    ping();
    ping();
    ping();

    let calls: i32 = CALLS as i32;
    print(&calls, .I32);
    putchar(10);

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
