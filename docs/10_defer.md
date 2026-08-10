# defer

`defer` schedules a statement to run at the end of the enclosing scope.
It runs even if the scope exits early via `return`.

```rust
use "std/io.cnd";

fn main() -> i32 {
    defer {
        println("cleanup (runs first)");
    }
    println("doing work");
    return 0;
}
```

```text
$ ./defer
doing work
cleanup (runs first)
```

## LIFO order

Deferred statements run in reverse order: the last `defer` runs first.

```rust
use "std/io.cnd";

fn main() -> i32 {
    defer { println("1"); }
    defer { println("2"); }
    defer { println("3"); }
    return 0;
}
```

```text
$ ./defer_order
3
2
1
```

## defer with a condition

A `defer` can carry a condition, which is evaluated at exit time.

```rust
use "std/io.cnd";

fn main() -> i32 {
    let flag = 1;
    defer if flag != 0 { println("flagged"); };
    return 0;
}
```

```text
$ ./defer_if
flagged
```

## defer and return

The deferred code runs before the function actually returns.

```rust
use "std/io.cnd";

fn early() -> i32 {
    defer { println("deferred"); }
    println("early");
    return 7;
}

fn main() -> i32 {
    let v = early();
    print(&v, .I32);
    putchar(10);
    return 0;
}
```

```text
$ ./defer_return
early
deferred
7
```

`defer` is the idiomatic way to close resources: open in one place, free at
scope exit.
