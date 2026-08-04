# Types and Literals

Cinder has integer types of every width, floats, `bool`, `char`, and strings.

## Integers

| Type | Bits | Range |
|------|------|-------|
| `u8`, `i8` | 8 | 0..255, -128..127 |
| `u16`, `i16` | 16 | 0..65535, -32768..32767 |
| `u32`, `i32` | 32 | 0..4_294_967_295, -2_147_483_648..2_147_483_647 |
| `u64`, `i64` | 64 | large |
| `u128`, `i128` | 128 | very large |
| `usize`, `isize` | pointer width | depends on the target |

An integer literal is `i32` by default. A suffix changes the type, and `_`
separates digits.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let a = 42;          // i32
    let b = 42u32;       // u32
    let c = 0xFF;        // hexadecimal, i32 = 255
    let d = 0b1010;      // binary, i32 = 10
    let e = 0o755;       // octal, i32 = 493
    let f = 1_000_000;   // 1000000
    let g = 255u8;       // fits: u8
    print_i32(a + c);
    print_newline();
    print_u32(b);
    print(" ");
    print_i32(d + e + f);
    print_newline();
    print_u32(g as u32);
    print_newline();
    return 0;
}
```

```text
$ ./ints
297
42 1000003
255
```

A literal must fit its type. `let h: u8 = 300;` is an error.
The negative sign is a unary operator, so `-1` on a `u8` is also an error.

## Floats

A float literal is `f64` by default; the `f32` suffix changes it.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let a = 3.14;        // f64
    let b = 3.14f32;     // f32
    print("pi ~= ");
    print_u32(a as u32);
    print_newline();
    return 0;
}
```

```text
$ ./floats
pi ~= 3
```

## bool

`true` and `false` are the two `bool` values.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let ok = true;
    let done = false;
    if ok && !done {
        println("going");
    }
    return 0;
}
```

```text
$ ./bool
going
```

## char

A character literal is a single ASCII byte in single quotes and has type
`i32`. Escape sequences are supported.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let letter = 'A';        // 65
    let esc = '\x1b';        // 27, the ESC byte
    let nl = '\n';           // 10, newline
    print_u32(letter as u32);
    print(" ");
    print_u32(esc as u32);
    print(" ");
    print_u32(nl as u32);
    print_newline();
    return 0;
}
```

```text
$ ./chars
65 27 10
```

## Strings

A string literal has type `[]u8`: a slice of bytes. Four prefixes exist:

| Prefix | Meaning |
|--------|---------|
| none | escapes are processed |
| `r` | raw string, escapes kept as-is |
| `b` | byte string, escapes kept as-is |
| `c` | C string, null-terminated, type `*u8` |

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let s = "Hello\nWorld";        // []u8, real newline inside
    let raw = r"C:\temp";          // []u8, backslashes kept
    let cstr = c"nul-terminated";  // *u8
    println(s);
    println(raw);
    print_cstr(cstr);
    print_newline();
    return 0;
}
```

```text
$ ./strings
Hello
World
C:\temp
nul-terminated
```

String indexing returns a byte. Iterating a string visits its bytes.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let s = "abc";
    print_u32(s[1] as u32);   // 98 = 'b'
    print_newline();
    for b in s {
        print_u32(b as u32);
        print(" ");
    }
    print_newline();
    return 0;
}
```

```text
$ ./bytes
98
97 98 99
```

> Slices and the `c"..."` C-string type are covered in
> [Arrays and Slices](08_arrays_slices.md) and
> [Calling C](14_extern_ffi.md).
