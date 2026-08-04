# Optionals and Errors

Cinder has no `NULL` in safe code. Missing values use `?T`, and failure uses
`!T`.

## Optionals

`?T` is either a `T` value or `none`.

```cinder
use "std/io.cnd";

fn maybe_name(id: i32) -> ?[]u8 {
    if id == 0 {
        return none;
    }
    return "cinder";
}

fn main() -> i32 {
    let a = maybe_name(0);
    let b = maybe_name(7);
    let x = a else { println("a is none"); return 0; };
    println(x);
    let y = b else { return 2; };
    println(y);
    return 0;
}
```

```text
$ ./optionals
a is none
```

## else bindings

`let x = v else { ... };` unwraps the optional. If it is `none`, the block
runs and the binding fails; the block must leave the function (return, break,
or panic).

```cinder
use "std/io.cnd";

fn show(v: ?i32) -> i32 {
    let x = v else { return 0; };
    print_i32(x);
    print_newline();
    return 1;
}

fn main() -> i32 {
    show(42);
    show(none);
    return 0;
}
```

```text
$ ./else_bind
42
```

## Error types

`!T` is either a `T` value or an error. Errors are usually enum variants.

```cinder
use "std/io.cnd";

enum Err {
    DivisionByZero;
}

fn safe_div(a: i32, b: i32) !i32 {
    if b == 0 {
        return Err.DivisionByZero;
    }
    return a / b;
}

fn main() -> i32 {
    let r = safe_div(10, 2) else {
        println("error");
        return 1;
    };
    print_i32(r);
    print_newline();

    let bad = safe_div(1, 0) else {
        println("division by zero");
        return 0;
    };
    return 2;   // unreachable
}
```

```text
$ ./errors
5
division by zero
```

## The `?` operator

Inside a function that returns an error type, `?` propagates the error.

```cinder
use "std/io.cnd";

enum Err {
    DivideByZero;
    Negative;
}

fn checked(a: i32, b: i32) !i32 {
    if b == 0 { return Err.DivideByZero; }
    if a < 0 { return Err.Negative; }
    return a / b;
}

fn half(a: i32) !i32 {
    let q = checked(a, 2)?;
    return q;
}

fn main() -> i32 {
    let h = half(10) else { return 1; };
    print_i32(h);
    print_newline();

    let bad = half(-4) else { println("error propagated"); return 0; };
    return 2;   // unreachable
}
```

```text
$ ./propagate
5
error propagated
```

## Optionals in the standard library

Lookups return `?T`: `read_byte() -> ?u8`, `vec_get() -> ?u8`,
`str_index_of() -> ?usize`. Parse helpers return `?T` too:

```cinder
use "std/io.cnd";
use "std/core/str.cnd";

fn main() -> i32 {
    let n = str_parse_i64("1234") else { return 1; };
    print_i64(n);
    print_newline();
    return 0;
}
```

```text
$ ./parse
1234
```
