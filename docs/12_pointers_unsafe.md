# Pointers and Unsafe

Safe code cannot read arbitrary memory. Raw pointers exist, but every
dereference, arithmetic, or cast on them must happen inside an `unsafe` block.

## Address-of is safe

Taking the address of a local is safe. Dereferencing requires `unsafe`.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let mut x = 5;
    let p = &x;
    unsafe {
        *p += 10;
    }

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
    unsafe {
        let t = *a;
        *a = *b;
        *b = t;
    }
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
    unsafe {
        let first = *p;

        let v: i32 = first as i32;
        print(&v, .I32);
    }
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

`*void` is a pointer to an unknown type. Any pointer coerces to `*void`;
converting back requires an unsafe cast.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let mut n: u64 = 42;
    let opaque: *void = &n;
    unsafe {
        let back: *u64 = opaque as *u64;

        let v = *back;
        print(&v, .U64);
    }
    putchar(10);
    return 0;
}
```

```text
$ ./voidptr
42
```

## Pointer arithmetic

Arithmetic on pointers (and indexing) is `unsafe`.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let arr = [10, 20, 30];
    let base = arr[..].ptr;   // convert the array to a slice, take its ptr
    unsafe {
        let v1 = *base;
        print(&v1, .I32);

        let sp: []u8 = " ";
        print(&sp, .S);

        let v2 = *(base + 1);
        print(&v2, .I32);
        putchar(10);
    }
    return 0;
}
```

```text
$ ./ptradd
10 20
```

## unsafe functions

A function marked `unsafe` may be called only inside an `unsafe` block. Its
body is already unsafe.

```rust
use "std/io.cnd";

unsafe fn read_u32(p: *u32) -> u32 {
    return *p;
}

fn main() -> i32 {
    let v: u32 = 7;
    unsafe {
        let got = read_u32(&v);

        let out: i32 = got as i32;
        print(&out, .I32);
        putchar(10);
    }
    return 0;
}
```

```text
$ ./unsafe_fn
7
```

## asm

Inline assembly is available inside `unsafe`.

```rust
// docs: kernel
unsafe {
    asm("wfi");
}
```

See [Bare Metal](17_bare_metal.md) for how this is used in a kernel.
