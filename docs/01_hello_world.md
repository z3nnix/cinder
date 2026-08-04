# Hello, World

The smallest Cinder program prints a line and returns the exit code `0`.

```cinder
use "std/io.cnd";

fn main() -> i32 {
    println("Hello, world!");
    return 0;
}
```

```text
$ ./cinder build hello.cnd --emit=bin -o hello
$ ./hello
Hello, world!
```

## How it works

- `use "std/io.cnd";` imports the standard I/O module.
- `fn main() -> i32` is the entry point. `i32` is the return type.
- `println(s)` writes a string and a newline to stdout.
- `return 0;` is the process exit code. `0` means success.

## Exit codes

The return value of `main` becomes the exit code of the program.

```cinder
// docs: check
fn main() -> i32 {
    return 3;
}
```

```text
$ ./cinder build exit.cnd --emit=bin -o exit
$ ./exit
$ echo $?
3
```

## Without a return value

`main` may also be a void function. The exit code is then `0`.

```cinder
use "std/io.cnd";

fn main() {
    println("done");
}
```

```text
$ ./hello
done
```

> `cinder` is the command-line wrapper. `./cinder check file.cnd` runs only the
> compiler checks; `./cinder build` produces a binary.
