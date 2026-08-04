# The Standard Library

Modules under `std/` ship with the compiler and are always on the include
path. Load them with `use`.

## I/O

`std/io.cnd` has print helpers and readers.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    println("hello");
    print_i32(42);
    print(" ");
    print_hex_u64(0x2a as u64);
    print_newline();
    return 0;
}
```

```text
$ ./io
hello
42 2a
```

| Function | Writes |
|----------|--------|
| `print(s)` / `println(s)` | string, optional newline |
| `print_i32/n/u32/u64/i64/u128/i128` | decimal integer |
| `print_hex_u8/u32/u64` | lowercase hex |
| `print_cstr(p)` | C string (null-terminated) |
| `print_err(s)` / `println_err(s)` | stderr |
| `read_byte() -> ?u8` | one byte from stdin, `none` on EOF |

## Vec

`std/vec.cnd` is a growable byte buffer. Functions take a pointer to the
struct; methods would be pointless without mutation.

```cinder
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
    print_u32(total);
    print_newline();
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

```cinder
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

```cinder
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

```cinder
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
        print(p[..3]);
    }
    print_newline();
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
