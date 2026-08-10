# Structs

A `struct` groups named, typed fields.

```rust
use "std/io.cnd";

struct Point {
    x: i32;
    y: i32;
}

fn main() -> i32 {
    let p = Point { x: 3, y: 4 };

    let x = p.x;
    print(&x, .I32);

    let sep: []u8 = ", ";
    print(&sep, .S);

    let y = p.y;
    print(&y, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./structs
3, 4
```

## Mutating a field

The binding must be `mut`, and the field must be assigned, not the whole
struct.

```rust
use "std/io.cnd";

struct Counter {
    value: i32;
    step: i32;
}

fn main() -> i32 {
    let mut c = Counter { value: 0, step: 2 };
    c.value += c.step;
    c.value += c.step;

    print(&c.value, .I32);
    putchar(10);
    return 0;
}
```

```text
$ ./mut_struct
4
```

## Functions on structs

Cinder has no methods; a function takes a pointer to the struct. This is the
usual "method" pattern.

```rust
use "std/io.cnd";

struct Rect {
    w: i32;
    h: i32;
}

fn area(r: *Rect) -> i32 {
    return r.w * r.h;
}

fn grow(r: *Rect, k: i32) {
    r.w *= k;
    r.h *= k;
}

fn main() -> i32 {
    let mut box = Rect { w: 3, h: 4 };

    let a1 = area(&box);
    print(&a1, .I32);
    putchar(10);

    grow(&box, 2);

    let a2 = area(&box);
    print(&a2, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./methods
12
48
```

Field access through a pointer is automatic: `r.w` reads through `r`.

## Sized, aligned, offset

`sizeof(T)`, `alignof(T)`, and `offsetof(T, field)` are compile-time
constants. They match the C ABI of the target.

```rust
use "std/io.cnd";

struct Pair {
    a: i32;
    b: u8;
}

static_assert(sizeof(Pair) == 8);
static_assert(alignof(Pair) == 4);
static_assert(offsetof(Pair, a) == 0);
static_assert(offsetof(Pair, b) == 4);

fn main() -> i32 {
    let sz: u64 = sizeof(Pair) as u64;
    print(&sz, .U64);

    let sp: []u8 = " ";
    print(&sp, .S);

    let off: u64 = offsetof(Pair, b) as u64;
    print(&off, .U64);
    putchar(10);

    return 0;
}
```

```text
$ ./layout
8 4
```

See [Compile-Time Code](11_compile_time.md) for more on `static_assert`.
