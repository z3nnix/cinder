# Enums

An `enum` is a type with named variants.

```rust
use "std/io.cnd";

enum Color {
    Red;
    Green;
    Blue;
}

fn name(c: Color) -> []u8 {
    switch c {
        Color.Red => { return "red"; }
        Color.Green => { return "green"; }
        Color.Blue => { return "blue"; }
    }
}

fn main() -> i32 {
    println(name(Color.Red));
    println(name(Color.Green));
    println(name(Color.Blue));
    return 0;
}
```

```text
$ ./enums
red
green
blue
```

## Dot shorthand

When the type is known, the variant can be written as `.Variant`.

```rust
use "std/io.cnd";

enum Direction {
    North;
    East;
    South;
    West;
}

fn arrow(d: Direction) -> []u8 {
    switch d {
        .North => { return "^"; }
        .East => { return ">"; }
        .South => { return "v"; }
        .West => { return "<"; }
    }
}

fn main() -> i32 {
    println(arrow(Direction.East));
    println(arrow(.West));
    return 0;
}
```

```text
$ ./shorthand
>
<
```

## Enums in errors

An enum is the natural error type. Returning a variant from a `!T` function
signals an error. See [Optionals and Errors](09_optionals_errors.md).

```rust
enum IoError {
    NotFound;
    PermissionDenied;
    DeviceBusy;
}
```

## Enums are plain values

An enum value is stored as its variant index. Use `switch` to branch.
Converting an enum to its index is an unsafe cast:

```rust
unsafe {
    let idx = Color.Blue as i32;   // 2
}
```
