# Modules

A module is a `.cnd` file. `use` imports one; `export` marks what is public.
Everything else is private to the module.

## Writing a module

```rust
// lib/queue.cnd
export struct Queue {
    data: [16]u8;
    head: u8;
    tail: u8;
}

export fn q_init() -> Queue {
    return Queue { data: [0; 16], head: 0, tail: 0 };
}

export fn q_push(q: *Queue, v: u8) {
    q.data[q.tail] = v;
    q.tail += 1;
}

export fn q_pop(q: *Queue) -> u8 {
    let v = q.data[q.head];
    q.head += 1;
    return v;
}

fn q_secret() { }    // private: not visible to importers
```

## Using the module

The path is resolved relative to the current file, then against the include
directories. `std/` is always on the search path.

```rust
// docs: skip
use "queue.cnd";
use "std/io.cnd";

fn main() -> i32 {
    let mut q = q_init();
    q_push(&q, 7);
    q_push(&q, 9);

    let a: i32 = q_pop(&q) as i32;
    print(&a, .I32);

    let sp: []u8 = " ";
    print(&sp, .S);

    let b: i32 = q_pop(&q) as i32;
    print(&b, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./modules
7 9
```

To build: `./cinder build main.cnd --emit=bin -o main -I lib`.

## export

`export` works on functions, structs, enums, constants, statics, and extern
functions.

```rust
export const VERSION = 1;
export static SEED: u32 = 0x1234;

export extern fn puts(s: []u8) -> i32;
```

## Target filter

`#[target("...")]` restricts a declaration to one target. Known targets are
`x86_64` and `x86_64-freestanding`.

```rust
// docs: skip
#[target("x86_64-freestanding")]
fn uart_putc(c: u8) { }
```
