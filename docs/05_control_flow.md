# Control Flow

## if / else

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let temp = 24;
    if temp > 30 {
        println("hot");
    } else if temp > 20 {
        println("warm");
    } else {
        println("cold");
    }
    return 0;
}
```

```text
$ ./ifelse
warm
```

## if as an expression

An `if` can produce a value. Both branches must have the same type.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let n = 7;
    let label = if n % 2 == 0 { "even" } else { "odd" };
    println(label);
    return 0;
}
```

```text
$ ./ifexpr
odd
```

## loop

`loop` repeats forever. `break` stops it, `continue` jumps to the next
iteration.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let mut i = 0;
    loop {
        i += 1;
        if i % 2 == 0 { continue; }
        if i > 7 { break; }
        print_i32(i);
        print(" ");
    }
    print_newline();
    return 0;
}
```

```text
$ ./loop
1 3 5 7
```

## while

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let mut n = 1;
    while n < 100 {
        n *= 2;
    }
    print_i32(n);
    print_newline();
    return 0;
}
```

```text
$ ./while
128
```

## for over ranges

`0..10` is exclusive, `0..=10` is inclusive. The loop variable is `i32`
(or the annotated type).

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let mut sum = 0;
    for i in 0..=10 {
        sum += i;
    }
    print_i32(sum);   // 0+1+...+10 = 55
    print_newline();
    return 0;
}
```

```text
$ ./forrange
55
```

A `usize` range is useful for indexing.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let s = "abc";
    for i in 0usize..s.len {
        print_u32(s[i] as u32);
    }
    print_newline();
    return 0;
}
```

```text
$ ./foridx
979899
```

## for over values

The `for v in coll` form iterates arrays, slices, and strings.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let primes = [2, 3, 5, 7];
    let mut total = 0;
    for p in primes {
        total += p;
    }
    print_i32(total);
    print_newline();
    return 0;
}
```

```text
$ ./foriter
17
```

## switch

`switch` can match integers, integer ranges, enums, and strings. A final
`else` handles everything else.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    let code = 3;
    switch code {
        0 => println("zero");
        1..3 => println("small");
        else => println("large");
    }
    return 0;
}
```

```text
$ ./switch
small
```

Switch cases are alternatives; execution does not fall through to the next
case. See [Enums](07_enums.md) for enum matching.
