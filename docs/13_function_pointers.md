# Function Pointers

A function type is `fn(Params) -> Ret`. Assign a bare function name to get a
pointer-sized value, then call it normally.

```rust
use "std/io.cnd";

fn double(v: i32) -> i32 { return v * 2; }
fn triple(v: i32) -> i32 { return v * 3; }

fn apply(f: fn(i32) -> i32, v: i32) -> i32 {
    return f(v);
}

fn main() -> i32 {
    let f: fn(i32) -> i32 = double;
    print_i32(apply(f, 5));
    print(" ");
    print_i32(apply(triple, 5));
    print_newline();
    return 0;
}
```

```text
$ ./fnptr
10 15
```

`&double` works too; it is the same value.

## Callbacks

Function types are ordinary values: variables, parameters, struct fields, and
extern signatures.

```rust
use "std/io.cnd";

fn on_key(key: u8) {
    print_u32(key);
    print(" ");
}

fn main() -> i32 {
    let handler: fn(u8) = on_key;
    handler('a' as u8);
    handler('b' as u8);
    print_newline();
    return 0;
}
```

```text
$ ./callback
97 98
```

## null function pointers

`null` is assignable to a function type, and function pointers can be compared
against `null`.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let f: fn() = null;
    if f == null {
        println("not set");
    }
    return 0;
}
```

```text
$ ./fnnull
not set
```

## Dispatch tables

A struct of function pointers is a tiny vtable.

```rust
use "std/io.cnd";

struct Format {
    header: fn() -> []u8;
    body: fn(i32) -> []u8;
}

fn csv_header() -> []u8 { return "col,col"; }
fn csv_body(v: i32) -> []u8 { return "csv"; }

fn json_header() -> []u8 { return "{"; }
fn json_body(v: i32) -> []u8 { return "}"; }

fn emit(fmt: *Format, v: i32) {
    println(fmt.header());
    println(fmt.body(v));
}

fn main() -> i32 {
    let csv = Format { header: csv_header, body: csv_body };
    let json = Format { header: json_header, body: json_body };
    emit(&csv, 1);
    emit(&json, 2);
    return 0;
}
```

```text
$ ./dispatch
col,col
csv
{
}
```
