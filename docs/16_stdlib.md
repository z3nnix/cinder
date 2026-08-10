# The Standard Library

Modules under `std/` ship with the compiler and are always on the include
path. Load them with `use`.

## I/O

`std/io.cnd` has print helpers and readers.

```rust
use "std/io.cnd";

fn main() -> i32 {
    println("hello");

    let n = 42;
    print(&n, .I32);

    let sp: []u8 = " ";
    print(&sp, .S);

    let big: u64 = 7;
    print(&big, .U64);
    putchar(10);

    return 0;
}
```

```text
$ ./io
hello
42 7
```

| Function | Writes |
|----------|--------|
| `print(&x, .Tag)` | one value, selected by tag |
| `println(s)` | string plus newline |
| `putchar(c)` | one byte |
| `print_err(s)` / `println_err(s)` | stderr |
| `read_byte() -> ?u8` | one byte from stdin, `none` on EOF |

The print tags are `I32`, `I64`, `I128`, `U8`, `U64`, `U128`, `F64`,
`Bool`, `S` (a `[]u8` string), and `Ptr`.

## Vec

`std/vec.cnd` is a growable byte buffer. Functions take a pointer to the
struct; methods would be pointless without mutation.

```rust
use "std/io.cnd";
use "std/vec.cnd";

fn main() -> i32 {
    let mut v = Vec { data: null, len: 0, cap: 0 };
    vec_init(&v);
    let ok = vec_push(&v, 10) && vec_push(&v, 20) && vec_push(&v, 30);
    if !ok { return 1; }
    let mut total: u32 = 0;
    for i in 0..vec_len(&v) {
        let b = vec_get(&v, i) else { return 2; };
        total += b;
    }

    let out: i32 = total as i32;
    print(&out, .I32);
    putchar(10);

    vec_deinit(&v);
    return 0;
}
```

```text
$ ./vec
60
```

`vec_from_slice(s)` builds a vector from a string.

## String

`std/string.cnd` is an owning, growable string built on Vec.

```rust
use "std/io.cnd";
use "std/string.cnd";

fn main() -> i32 {
    let mut s = string_from("cin");
    if !string_push_byte(&s, 'd' as u8) { return 1; }
    if !string_append(&s, "er") { return 2; }
    println(string_as_slice(&s));
    string_deinit(&s);
    return 0;
}
```

```text
$ ./string
cinder
```

## Str helpers

`std/core/str.cnd` is pure and allocation-free.

```rust
use "std/io.cnd";
use "std/core/str.cnd";

fn main() -> i32 {
    let s = "  cinder  ";
    let t = str_trim(s);
    println(t);
    if str_starts_with(t, "cin") {
        println("starts with cin");
    }
    return 0;
}
```

```text
$ ./str
cinder
starts with cin
```

## Math, memory, ascii

`std/core/math.cnd` (`math_max`, `math_gcd`, `math_is_pow2`, ...),
`std/core/mem.cnd` (`mem_copy`, `mem_zero`, `mem_align_up`, ...), and
`std/core/ascii.cnd` (`ascii_is_digit`, `ascii_to_upper`, ...) are tiny,
portable helpers.

## Allocator

`std/alloc.cnd` exposes `alloc(n)`, `alloc_realloc(p, n)`, and `dealloc(p)`
backed by libc on hosted targets.

```rust
use "std/io.cnd";
use "std/alloc.cnd";

fn main() -> i32 {
    let p = alloc(16);
    if p == null { return 1; }
    unsafe {
        p[0] = 65;
        p[1] = 66;
        p[2] = 67;
        p[3] = 0;
        let slice = p[..3];
        print(&slice, .S);
    }
    putchar(10);
    dealloc(p);
    return 0;
}
```

```text
$ ./alloc
ABC
```

## Port I/O and panic

`std/x86.cnd` declares `outb`/`inb`/etc. for bare-metal; `std/panic.cnd`
defines `panic(msg)` which aborts the program.
