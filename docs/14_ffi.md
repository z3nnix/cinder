# FFI: Calling C

`extern fn` declares a function defined outside the program. It links against
the system C library by default.

```cinder
use "std/io.cnd";

extern fn abs(n: i32) -> i32;

fn main() -> i32 {
    print_i32(abs(-42));
    print_newline();
    return 0;
}
```

```text
$ ./extern
42
```

The example above links to libc: `abs` is resolved at link time.

## c-strings

The `c"..."` literal produces a `[]u8` with a trailing zero byte, the form C
functions expect. `c"hello"` can be passed directly to C functions that accept
a pointer - the trailing null is part of the string.

```cinder
// docs: skip
use "std/io.cnd";

extern fn my_strlen(s: *u8) -> usize;

fn main() -> i32 {
    let msg = c"hello, libc!";
    print_u64(my_strlen(msg) as u64);
    print_newline();
    return 0;
}
```

```text
$ ./cstr
13
```

## Pointers and memory

C functions that return allocations come back as raw pointers. Dereferencing
and indexing them is `unsafe`.

```cinder
use "std/io.cnd";

extern fn malloc(size: usize) -> *u8;
extern fn free(p: *u8);

fn main() -> i32 {
    let p = malloc(64);
    unsafe {
        p[0] = 65;
        p[1] = 66;
        p[2] = 67;
        p[3] = 0;
        print(p[..3]);
    }
    print_newline();
    free(p);
    return 0;
}
```

```text
$ ./malloc
ABC
```

## Layout compatibility

Structs use the C ABI: sizes, alignments, and offsets match C on the same
target. Use `sizeof`/`offsetof` to stay in sync (see
[Compile-Time Code](11_compile_time.md)).

```cinder
struct timespec {
    tv_sec: i64;
    tv_nsec: i64;
}
```

## Variadic functions

An ellipsis `...` marks the variadic part of an extern signature. This is how
`printf` is declared in the standard library:

```cinder
// docs: skip
extern fn printf(fmt: *u8, ...) -> i32;
```

Call it like C:

```cinder
// docs: skip
printf(c"%s\n", p);
```

Use `fflush(null)` after `printf` when mixing with Cinder's buffered output.
