# Functions

Functions start with `fn`, take typed parameters, and return one value.

```rust
use "std/io.cnd";

fn add(a: i32, b: i32) -> i32 {
    return a + b;
}

fn describe(n: i32) -> []u8 {
    if n > 0 {
        return "positive";
    }
    return "not positive";
}

fn main() -> i32 {
    print_i32(add(2, 3));
    print_newline();
    println(describe(5));
    println(describe(-1));
    return 0;
}
```

```text
$ ./fns
5
positive
not positive
```

## Parameters

Parameters are read-only. Pass by value; pass a pointer to mutate the caller's
value (see [Pointers](12_pointers_unsafe.md)).

```rust
fn scale(v: i32, k: i32) -> i32 {
    return v * k;
}
```

## void

A function without a return type returns nothing.

```rust
use "std/io.cnd";

fn announce(tag: []u8) {
    print("[");
    print(tag);
    print("] ");
    println("running");
}

fn main() -> i32 {
    announce("boot");
    return 0;
}
```

```text
$ ./void
[boot] running
```

## Early return

`return` exits the function immediately.

```rust
use "std/io.cnd";

fn classify(v: i32) -> []u8 {
    if v < 0 {
        return "negative";
    }
    if v == 0 {
        return "zero";
    }
    return "positive";
}

fn main() -> i32 {
    println(classify(-5));
    println(classify(0));
    println(classify(5));
    return 0;
}
```

```text
$ ./early
negative
zero
positive
```

## unsafe fn

A function may itself be marked `unsafe`. Its body is treated as an `unsafe`
block, and every call site must be inside `unsafe`.

```rust
use "std/io.cnd";

unsafe fn peek(v: *u32) -> u32 {
    return *v;
}

fn main() -> i32 {
    let secret: u32 = 42;
    unsafe {
        let got = peek(&secret);
        print("peek = ");
        print_u32(got);
        print_newline();
    }
    return 0;
}
```

```text
$ ./unsafe_fn
peek = 42
```

```text
$ ./unsafe_fn
read = 42
```
