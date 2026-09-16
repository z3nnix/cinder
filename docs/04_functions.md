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
    let v = add(2, 3);
    print(&v, .I32);
    putchar(10);

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
value (see [Pointers](12_pointers.md)).

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
    let open: []u8 = "[";
    print(&open, .S);
    print(&tag, .S);

    let close: []u8 = "] ";
    print(&close, .S);
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

`unsafe fn` is deprecated and has no effect. The `unsafe` keyword before `fn`
is accepted for compatibility, but the function body and every call site behave
like any other function. The construct will be removed in a future version.

```rust
// docs: error-skip
unsafe fn peek(v: *u32) -> u32 {
    return *v;
}
```
