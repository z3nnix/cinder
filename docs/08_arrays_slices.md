# Arrays and Slices

An array is a fixed-length sequence. A slice is a view into memory: a pointer
and a length.

## Arrays

The type `[N]T` is an array of N values of type T.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let primes: [4]i32 = [2, 3, 5, 7];
    let zeroes = [0; 8];        // repeat literal: eight zeroes

    let v1 = primes[2];
    print(&v1, .I32);

    let sp: []u8 = " ";
    print(&sp, .S);

    let v2 = zeroes[4];
    print(&v2, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./arrays
5 0
```

The repeat literal `[v; n]` fills an array with the same value.

## Bounds checking

In debug mode an out-of-bounds index traps. Constant indexes are checked at
compile time; runtime indexes are checked in debug builds.

```rust
// docs: error
fn main() -> i32 {
    let a = [1, 2, 3];
    return a[9];    // compile-time error: index out of bounds
}
```

## Slices

The type `[]T` is a slice. Slices are made by slicing an array, taking an
existing slice, or using a string literal.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let arr = [10, 20, 30, 40, 50];
    let s = arr[1..4];          // [20, 30, 40]

    let len: i32 = s.len as i32;
    print(&len, .I32);

    let sp: []u8 = " ";
    print(&sp, .S);

    let first = s[0];
    print(&first, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./slices
3 20
```

A slice keeps a pointer and a length: `s.ptr` and `s.len`.

```rust
use "std/io.cnd";

fn total(vals: []i32) -> i32 {
    let mut t = 0;
    for v in vals {
        t += v;
    }
    return t;
}

fn main() -> i32 {
    let nums = [1, 2, 3, 4];

    let t1 = total(nums[..]);   // [..] converts the array to a slice
    print(&t1, .I32);
    putchar(10);

    let t2 = total(nums[1..3]);
    print(&t2, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./slice_fn
10
5
```

## Strings are slices

A string literal is a `[]u8`. Its `.ptr` points at the first byte.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let s = "hello";

    let len: u64 = s.len as u64;
    print(&len, .U64);

    let sp: []u8 = " ";
    print(&sp, .S);

    let first: i32 = s[0] as i32;
    print(&first, .I32);
    putchar(10);

    return 0;
}
```

```text
$ ./strslice
5 104
```

## The full slice operator

`[..]`, `[a..]`, `[..b]`, and `[a..b]` all work.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let s = "abcdef";
    println(s[2..5]);
    println(s[1..]);
    println(s[..3]);
    return 0;
}
```

```text
$ ./sliceops
cde
bcdef
abc
```
