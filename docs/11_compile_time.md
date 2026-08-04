# Compile-Time Code

Constants are evaluated at compile time. Sizes, alignments, and offsets are
constant expressions.

## const

```cinder
use "std/io.cnd";

const SPEED_OF_LIGHT = 299_792_458;
const TIMEOUT_MS: u32 = 1000;

fn main() -> i32 {
    print_i32(SPEED_OF_LIGHT);
    print(" ");
    print_u32(TIMEOUT_MS);
    print_newline();
    return 0;
}
```

```text
$ ./consts
299792458 1000
```

## static_assert

`static_assert` fails the build if the condition is false.

```cinder
use "std/io.cnd";

static_assert(4 * 4 == 16);
static_assert(sizeof(u32) == 4);
static_assert(sizeof(usize) == 8);   // on x86_64

fn main() -> i32 {
    println("built");
    return 0;
}
```

```text
$ ./sassert
built
```

A failing assertion stops compilation:

```cinder
// docs: error
static_assert(1 == 2);
fn main() -> i32 { return 0; }
```

## sizeof, alignof, offsetof

These follow the C ABI of the target, so shared structs agree with C.

```cinder
use "std/io.cnd";

struct Record {
    id: u32;
    flags: u8;
    payload: u64;
}

static_assert(offsetof(Record, payload) == 8);

fn main() -> i32 {
    print_u64(sizeof(Record) as u64);
    print(" ");
    print_u64(alignof(Record) as u64);
    print(" ");
    print_u64(offsetof(Record, payload) as u64);
    print_newline();
    return 0;
}
```

```text
$ ./layout2
16 8 8
```

## const in types

A constant can be used where a compile-time number is expected.

```cinder
use "std/io.cnd";

const BUFFER_CAP = 64;

fn main() -> i32 {
    let buf: [BUFFER_CAP]u8 = [0; BUFFER_CAP];
    print_u64(sizeof([BUFFER_CAP]u8) as u64);
    print_newline();
    return 0;
}
```

```text
$ ./const_types
64
```

## Compile-time in depth

`const` values are substituted and folded during compilation. Any expression
built from literals and other constants is constant. There is no separate
`comptime` evaluation phase: the compiler evaluates what it can, when it must
(array lengths, `static_assert`, `sizeof`).
