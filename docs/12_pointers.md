# Pointers

Raw pointers let you read and write memory through an address. Dereference,
arithmetic, indexing, and pointer casts are always available.

## Address-of

Taking the address of a local produces a pointer to it.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let mut x = 5;
    let p = &x;
    *p += 10;

    print(&x, .I32);
    putchar(10);
    return 0;
}
```

```text
$ ./pointers
15
```

## Passing pointers to functions

The usual "method" pattern: pass `&value`, mutate through the pointer.

```rust
use "std/io.cnd";

fn swap(a: *i32, b: *i32) {
    let t = *a;
    *a = *b;
    *b = t;
}

fn main() -> i32 {
    let mut x = 1;
    let mut y = 2;
    swap(&x, &y);

    print(&x, .I32);

    let sp: []u8 = " ";
    print(&sp, .S);

    print(&y, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./swap
2 1
```

## Pointer to a slice byte

A string is a slice; `s.ptr` points at its first byte.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let s = "hello";
    let p = s.ptr;
    let first = *p;

    let v: i32 = first as i32;
    print(&v, .I32);
    putchar(10);
    return 0;
}
```

```text
$ ./strptr
104
```

## null

The literal `null` is the null pointer. Never dereference it.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let p: *i32 = null;
    if p == null {
        println("null pointer");
    }
    return 0;
}
```

```text
$ ./null
null pointer
```

## Pointer qualifiers

`*const` reads only; `*volatile` reads/writes go around optimization.

```rust
let a: *const u32 = &value;      // read-only
let b: *volatile u32 = &reg;     // volatile access
let c: *const volatile u32 = &reg;
```

## *void

`*void` is a pointer to an unknown type. Any pointer coerces to `*void`
and may be cast back to a concrete pointer type.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let mut n: u64 = 42;
    let opaque: *void = &n;
    let back: *u64 = opaque as *u64;

    let v = *back;
    print(&v, .U64);
    putchar(10);
    return 0;
}
```

```text
$ ./voidptr
42
```

## Pointer arithmetic

Arithmetic on pointers (and indexing) steps through the pointee.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let arr = [10, 20, 30];
    let base = arr[..].ptr;   // convert the array to a slice, take its ptr
    let v1 = *base;
    print(&v1, .I32);

    let sp: []u8 = " ";
    print(&sp, .S);

    let v2 = *(base + 1);
    print(&v2, .I32);
    putchar(10);
    return 0;
}
```

```text
$ ./ptradd
10 20
```

## asm

Inline assembly is always available.

```rust
// docs: kernel
asm("wfi");
```

### Operands

Outputs come after the first `:`; inputs after the second.
Constraints are quoted strings; `=` marks a write-only output.

The output must be a mutable variable, pointer dereference, or index expression.

```rust
let mut out: u64 = 0;
asm("movq $1, $0" : "=r"(out) : "r"(42u64));

let mut a: i32 = 10;
let mut b: i32 = 20;
let mut sum: i32 = 0;
asm("addl $1, $2, $0" : "=r"(sum) : "r"(a), "r"(b));
```

The result of the expression is the output value.

See [Bare Metal](17_bare_metal.md) for how this is used in a kernel.