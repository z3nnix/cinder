# Cinder Language Specification

This document is the specification of the Cinder language.
This document describes the current behavior of the compiler.
This document uses Simplified Technical English (ASD-STE100).
Each sentence has one idea.
Each term has one meaning.
See the Glossary at the end of this document.

---

## 1. Purpose

Cinder is a small systems programming language.
Cinder compiles to LLVM IR.
Cinder is safe by default.
Cinder gives the programmer full control of the hardware.

The goal of Cinder is minimalism.
The programmer can learn Cinder in one day.
The compiler has few moving parts.
The compiler has no macros and no templates.

---

## 2. Design Principles

| Principle | Meaning |
|-----------|---------|
| Minimalism | The language is small. The keyword count is 20. |
| Explicitness | The code does what it says. There is no hidden behavior. |
| C compatibility | The syntax is close to C. The unsafe parts of C are removed. |
| Bare metal | There is no runtime. There is no hidden dependency. |
| Safety | Static analysis runs outside `unsafe` blocks. Optional types replace NULL. |
| Fast compilation | There are no macros and no templates. |
| LLVM IR | The compiler emits LLVM IR. LLVM optimizes the IR. |

---

## 3. Lexical Structure

### 3.1 Keywords

The keyword list is:

```
as break const continue defer else enum extern fn for if let loop mut
return switch unsafe use while volatile
```

The word `static` is a contextual keyword.
The word `struct` is a contextual keyword.
The word `export` is a contextual keyword.
The words `sizeof`, `alignof`, `offsetof`, and `static_assert` are contextual keywords.
The words `true`, `false`, `none`, and `null` are reserved literal spellings.

### 3.2 Comments

A line comment starts with `//`.
A line comment ends at the end of the line.

A block comment starts with `/*`.
A block comment ends with `*/`.
A block comment cannot be nested.

```cinder
// This is a line comment.

/*
   This is a block comment.
*/
```

### 3.3 Semicolons

A semicolon is required after each statement.
A semicolon or a comma is required after each struct field and each enum variant.
The trailing separator is allowed before the closing brace.

```cinder
let x = 10;        // correct
let y = 20         // error: semicolon missing
```

### 3.4 Identifiers

An identifier contains ASCII letters, digits, and the underscore.
The first character is a letter or the underscore.
Identifiers are case sensitive.

Variable names and function names use `snake_case`.
Struct names and enum names use `PascalCase`.

```cinder
let my_var = 10;
let _temp = 20;
fn uart_init() { }
struct UartConfig { }
enum Color { Red; Green; Blue; }
```

---

## 4. Literals

### 4.1 Integer Literals

An integer literal is a decimal number by default.
The default integer type is `i32`.

A type suffix changes the type.
A suffix is one of the integer type names.
Example: `42u32` is a `u32` value.

The underscore `_` is a digit separator.
The underscore does not change the value.

Cinder supports four bases:

| Prefix | Base | Example |
|--------|------|---------|
| none | 10 | `42` |
| `0x` | 16 | `0xFF` |
| `0b` | 2 | `0b1010` |
| `0o` | 8 | `0o755` |

```cinder
let a = 42;             // i32
let b = 42u32;          // u32
let c = 0xFF;           // i32, 255
let d = 0b1010;         // i32, 10
let e = 0o755;          // i32, 493
let f = 1_000_000;      // i32, 1000000
```

A literal must fit its target type.
The compiler reports an error when the literal does not fit.

```cinder
let a: u8 = 300;        // error: 300 does not fit in u8
let b: u8 = -1;         // error: -1 does not fit in u8
```

### 4.2 Float Literals

A float literal has a decimal point.
The default float type is `f64`.
The suffix `f32` or `f64` changes the type.

```cinder
let a = 3.14;           // f64
let b = 3.14f32;        // f32
```

### 4.3 Boolean Literals

The value `true` has type `bool`.
The value `false` has type `bool`.

### 4.4 Character Literals

A character literal is one character in single quotes.
A character literal has type `i32`.
The character is an ASCII character.

The escape sequences are:

| Sequence | Value |
|----------|-------|
| `\n` | newline (0x0A) |
| `\t` | tab (0x09) |
| `\r` | carriage return (0x0D) |
| `\0` | null (0x00) |
| `\\` | backslash |
| `\'` | single quote |
| `\"` | double quote |
| `\xNN` | the byte 0xNN, exactly two hex digits |

```cinder
let c = 'A';            // 65
let esc = '\x1b';       // 27, the ESC byte
```

### 4.5 String Literals

A string literal is a sequence of characters in double quotes.
A string literal has type `[]u8`.
A string literal stores bytes.

The escape sequences in Section 4.4 apply to normal strings.

The string prefixes are:

| Prefix | Meaning |
|--------|---------|
| none | normal string, escapes are processed |
| `r` | raw string, escapes are not processed |
| `b` | byte string, escapes are not processed |
| `c` | C string, stored with a trailing null byte, type `*u8` |

```cinder
let s = "Hello\nWorld";          // []u8
let raw = r"C:\Windows";         // []u8, backslashes kept
let data = b"raw bytes";         // []u8
let cstr = c"Hello\0";           // *u8, null-terminated
let esc = "\x1b[31m";            // []u8, starts with ESC
```

A string index returns a byte.

```cinder
let first = s[0];       // u8
```

---

## 5. Types

### 5.1 Primitive Types

| Type | Size (bits) | Meaning |
|------|-------------|---------|
| `u8`, `u16`, `u32`, `u64`, `u128` | as named | unsigned integer |
| `i8`, `i16`, `i32`, `i64`, `i128` | as named | signed integer, two's complement |
| `f32` | 32 | IEEE 754 float |
| `f64` | 64 | IEEE 754 float |
| `bool` | 8 | true or false |
| `usize` | pointer size | unsigned, platform width |
| `isize` | pointer size | signed, platform width |
| `void` | 0 | no value, functions only |

On the x86_64 target, `usize` and `isize` are 64 bits wide.

### 5.2 Arrays

An array has a fixed length.
The length is a compile-time constant.
The element type is uniform.

```cinder
let arr: [4]u8 = [10, 20, 30, 40];
let arr2 = [10, 20, 30, 40];       // [4]i32
```

### 5.3 Slices

A slice is a view into an array.
A slice stores a pointer and a length.
A slice is a value of type `[]T`.

```cinder
let slice: []u8 = arr[0..2];       // bytes 0 and 1
let slice2 = arr[1..];             // from index 1 to the end
let slice3 = arr[..3];             // from the start to index 2
let slice4 = arr[..];              // the whole array
```

A slice has the field `len`.
An array does not have the field `len`.

```cinder
let n = slice.len;
```

### 5.4 Pointers

A pointer stores an address.
The type `*T` is a pointer to T.
The literal `null` is the null pointer.

```cinder
let p: *u32 = &value;
let nil: *i32 = null;
```

Pointer qualifiers are:

```cinder
let a: *const u32 = ...;        // read-only pointer
let b: *volatile u32 = ...;     // volatile access
let c: *const volatile u32 = ...;
```

Pointer arithmetic requires an `unsafe` block.
Dereferencing a raw pointer requires an `unsafe` block.

The type `*void` is a pointer to an unknown type.
A pointer to a concrete type coerces implicitly to `*void`.
A `*void` value cannot be dereferenced, indexed, or sliced.
Converting `*void` back to a concrete pointer type requires an `unsafe` cast.

```cinder
extern fn memset(dst: *void, c: i32, n: usize) -> *void;

fn main() {
    let mut buf: [8]u8 = [0; 8];
    memset(&buf, 0, 8);                 // [8]u8 coerces to *void
    let p: *void = malloc(16) else { return; };
    unsafe {
        let q: *i32 = p as *i32;        // *void -> *i32 requires unsafe
    }
}
```

### 5.5 Optional Types

An optional type is `?T`.
A value of type `?T` is a value of type T or `none`.
Optional types replace NULL.

```cinder
let maybe: ?u32 = 42;
let nothing: ?u32 = none;
```

### 5.6 Error Types

An error type is `!T`.
A function can return a value of type `!T`.
The value is a plain value or an enum value that represents an error.

```cinder
fn read_sensor() !u16 {
    return 42;
}
```

### 5.7 void

The type `void` is allowed only as a function return type.
A function with no return type is a void function.

### 5.8 Function Types

A function type is written `fn(Params) -> Ret`.
The parameter list can be empty: `fn()`.
The return type can be omitted, in which case the function type returns `void`:

```cinder
let handler: fn(i32) -> i32 = double;   // bare function name
let printer: fn() = print_line;         // void-returning function type
let also: fn(i32) -> i32 = &double;     // & is allowed, same result
```

Function types are pointer-sized.
They may be used in variables, parameters, struct fields, and extern signatures.
A function pointer value is invoked with a normal call: `handler(x)`.

The literal `null` is assignable to a function type, and function pointers can be compared against `null`.
Function values are the functions themselves; the address-of operator `&` on a function name yields the same function pointer.

---

## 6. Variables

### 6.1 let

The keyword `let` declares a local variable.
The type is inferred when the type annotation is absent.

```cinder
let x = 42;             // type i32
let y: u32 = 100;       // type u32
```

A local variable must have an initializer.

```cinder
let z: u32;             // error: no initializer
let z: u32 = 0;         // correct
```

### 6.2 mut

A local variable is immutable by default.
The keyword `mut` makes a local variable mutable.

```cinder
let mut counter = 0;
counter += 1;
```

### 6.3 const

The keyword `const` declares a compile-time constant.
The type is optional.
A constant value must be computable at compile time.

```cinder
const MAX_SIZE = 4096;
const TIMEOUT_MS: u32 = 1000;
const PI = 3.14159;
```

### 6.4 static

The keyword `static` declares a global variable.
The type is optional.
A static variable has one instance in the whole program.

```cinder
static GLOBAL_COUNTER: u32 = 0;

fn increment() {
    GLOBAL_COUNTER += 1;
}
```

The `section` clause places a static variable in a named section.
This clause is for bare metal code.

```cinder
static MB_HEADER: [3]u32 = [0x1BADB002, 0, 0xE4524FFE] section(".multiboot");
```

### 6.5 Shadowing

Shadowing is allowed.
A new variable with the same name hides the old variable.

```cinder
let x = 10;
let x = x + 5;          // the new x, the old x is hidden
```

---

## 7. Functions

### 7.1 Definition

The keyword `fn` declares a function.

```cinder
fn add(a: i32, b: i32) -> i32 {
    return a + b;
}

fn log(msg: []u8) {
    // void function, no return value
}
```

### 7.2 Return Values

The keyword `return` returns a value.
The last expression of the body is the implicit return value.
The last expression must match the return type.

```cinder
fn mul(a: i32, b: i32) -> i32 {
    return a * b;
}

fn square(a: i32) -> i32 {
    a * a               // implicit return
}
```

### 7.3 unsafe fn

The keyword `unsafe` before `fn` declares an unsafe function.
An unsafe function body has the rights of an `unsafe` block.
An unsafe function must be called from an `unsafe` context.

```cinder
unsafe fn dangerous() {
    let ptr = 0x40001000 as *u32;
    *ptr = 1;
}
```

### 7.4 extern fn

The keyword `extern` before `fn` declares an external function.
An external function has no body.
The linker resolves the external function by name.
A call to an external function does not require `unsafe`.

```cinder
extern fn exit(code: i32);
extern fn write(fd: i32, buf: *u8, count: usize) -> isize;
```

An external function can be variadic.
The fixed parameters come first.
The ellipsis `...` marks the variadic part.

```cinder
extern fn printf(fmt: *u8, ...) -> i32;
```

An external function can take function pointers and `*void` parameters.
This is the bridge for C callbacks:

```cinder
extern fn atexit(cb: fn() -> void) -> i32;
extern fn qsort(base: *void, nmemb: usize, size: usize, compar: fn(*void, *void) -> i32);

fn goodbye() {
    println("bye");
}

fn main() {
    atexit(goodbye);          // pass a Cinder function to C
}
```

### 7.5 Function Attributes

The attribute keywords are `inline`, `naked`, `noreturn`, and `section`.
`inline` and `naked` can appear after `fn`.
All four attributes can appear at the end of the declaration.

```cinder
fn inline add_small(a: u8, b: u8) -> u8 inline {
    return a + b;
}

fn irq_handler() naked {
    unsafe { asm("push rdi"); }
}

fn panic() noreturn {
    loop { asm("hlt"); }
}

fn boot_entry() section(".boot") {
    // body
}
```

### 7.6 main

The program entry point is the function `main`.
The function `main` can return `i32`.
The process exit code is the return value of `main`.

```cinder
fn main() -> i32 {
    return 0;
}
```

---

## 8. Operators and Expressions

### 8.1 Binary Operators

The arithmetic operators are `+`, `-`, `*`, `/`, `%`.
These operators need numeric operands.
The modulo operator `%` follows the sign of the dividend.

The bitwise operators are `<<`, `>>`, `&`, `|`, `^`.
These operators need integer operands.

The comparison operators are `==`, `!=`, `<`, `<=`, `>`, `>=`.
These operators produce `bool`.

The logical operators are `&&`, `||`, `!`.
These operators need `bool` operands.

The assignment operators are `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `<<=`, `>>=`, `&=`, `|=`, `^=`.
The assignment operators work on mutable variables.

The unary operators are `-` and `!`.
The address-of operator is `&`.
The dereference operator is `*`.

### 8.2 Casts

The keyword `as` casts a value to a type.

```cinder
let a = 42 as f64;
let b = 3.14 as i32;
let c = 7 as u8;
```

Cinder supports safe numeric casts outside `unsafe`.
Other casts are allowed inside `unsafe`.

```cinder
unsafe {
    let reg = 0x40001000 as *u32;
}
```

### 8.3 Indexing and Slicing

The index operator reads an array element, a slice element, or a string byte.

```cinder
let v = arr[0];
let b = s[1];
```

A constant index outside the array length is an error.
A constant out-of-bounds index is an error outside `unsafe`.

```cinder
let x = arr[9];         // error when arr has length 3
```

The slice operator makes a slice from an array.

```cinder
let sl = arr[1..3];
```

### 8.4 if Expression

The `if` expression returns a value.
Both branches must have the same type.

```cinder
let max = if a > b { a } else { b };
```

### 8.5 Struct Literal

A struct literal names each field.

```cinder
let p = Point { x: 1, y: 2 };
```

A trailing comma is allowed.

```cinder
let p = Point { x: 1, y: 2, };
```

### 8.6 Array Literal

An array literal lists the elements.

```cinder
let arr = [1, 2, 3];
```

A trailing comma is allowed.

```cinder
let arr = [1, 2, 3,];
```

An array literal can repeat one element a constant number of times.

```cinder
let zeros: [64]u8 = [0; 64];
let rows = [1, 2; 3]; // error: the two forms do not mix
```

The count must be a non-negative constant integer.
The element expression is evaluated once.

### 8.7 Calls

A call passes arguments in the declared order.
A trailing comma is allowed.

```cinder
let s = sum(1, 2,);
```

The `?` operator on a call result is the error propagation operator.
Section 14 describes the `?` operator.

### 8.8 sizeof, alignof, offsetof

The type operator `sizeof(T)` is the size of T in bytes.
The type operator `alignof(T)` is the alignment of T in bytes.
The type operator `offsetof(T, field)` is the byte offset of a struct field.
All three return a `usize` value and are constant expressions.

```cinder
struct Pair {
    a: i32,
    b: u8,
}

const PAIR_SIZE: usize = sizeof(Pair);       // 8
const A_OFFSET: usize = offsetof(Pair, a);   // 0
const B_OFFSET: usize = offsetof(Pair, b);   // 4
```

A `struct` type may be written with or without the `struct` keyword prefix inside a type context:

```cinder
sizeof(struct Pair)   // same as sizeof(Pair)
```

The sizes, alignments, and offsets follow the C ABI of the target
(the LLVM DataLayout), so shared structs agree with C.
They are constant, so they can be used in `const`, array lengths, and `static_assert`.

---

## 9. Control Flow

### 9.1 if / else

```cinder
if x > 10 {
    do_something();
} else if x > 5 {
    do_other();
} else {
    fallback();
}
```

### 9.2 Loops

The `loop` statement repeats forever.
The `break` statement exits a loop.
The `continue` statement starts the next iteration.

```cinder
loop {
    if done { break; }
}
```

The `while` loop repeats while the condition is true.

```cinder
let mut i = 0;
while i < 10 {
    i += 1;
}
```

The `for` loop iterates over a range.
The range `a..b` excludes b.
The range `a..=b` includes b.

```cinder
for i in 0..10 {          // i = 0, 1, ..., 9
    do_work(i);
}
for i in 0..=5 {          // i = 0, 1, ..., 5
    do_work(i);
}
```

The `for` loop iterates over an array or a slice.

```cinder
let arr = [10, 20, 30];
for value in arr {
    log(value);
}
```

The `for` loop with two variables gives the index and the value.
The index type is `usize`.

```cinder
for i, value in arr {
    log(i as i32, value);
}
```

### 9.3 switch

The `switch` statement tests one value.
Each case has a pattern.
The `else` clause handles the remaining cases.

```cinder
let value = 42;
switch value {
    0 => log("zero");
    1..10 => log("small");
    42 => log("answer");
    else => log("other");
}
```

The `switch` statement tests an enum value.
The shorthand `.Name` form is allowed when the enum type is known.

```cinder
let c = Color.Red;
switch c {
    Color.Red => log("red");
    .Green => log("green");
    .Blue => log("blue");
}
```

### 9.4 static_assert

The statement `static_assert(cond);` checks a constant expression at compile time.
If the condition is false, the compiler reports an error.
The condition must be a constant expression.

`static_assert` may appear at the top level of a module or inside a function body.

```cinder
static_assert(sizeof(i32) == 4);
static_assert(sizeof(Pair) == 8);
static_assert(offsetof(Pair, b) == 4);

fn main() {
    static_assert(alignof(i64) == 8);
}
```

---

## 10. defer

The `defer` statement runs code at the end of the scope.
Deferred code runs in LIFO order.
The last deferred statement runs first.

```cinder
fn main() {
    defer log("1");
    defer log("2");       // this runs first
}
```

A `defer` statement can have a condition.

```cinder
defer if ptr != null { free(ptr); };
```

---

## 11. Structs

A struct groups named fields.
Each field has a type.

```cinder
struct Point {
    x: i32,
    y: i32,
}
```

A field separator is a semicolon or a comma.
The trailing separator is allowed.

A struct literal initializes the fields by name.

```cinder
let p = Point { x: 1, y: 2 };
```

The dot reads or writes a field.
Writing requires a mutable variable.

```cinder
let x = p.x;
let mut q = p;
q.y = 10;
```

A struct value is a plain data value.
Aggregate comparison is not supported.

```cinder
if p == q { }            // error: cannot compare structs
```

---

## 12. Enums

An enum lists named variants.
An enum variant carries no data.

```cinder
enum Color {
    Red;
    Green;
    Blue;
}
```

A variant separator is a semicolon or a comma.
The trailing separator is allowed.

The dot creates an enum value.

```cinder
let c = Color.Red;
```

The shorthand `.Name` form is allowed when the enum type is known.

```cinder
let c = .Red;
```

---

## 13. Optionals

An optional value is a value or `none`.
The `else` clause unwraps an optional.
The `else` block runs when the value is `none`.
After the `else` clause, the variable is the unwrapped value.

```cinder
let maybe: ?u32 = get_value();
let val = maybe else {
    return 0;
};
// here val has type u32
```

---

## 14. Errors

An error function returns a value of type `!T`.
The `?` operator propagates an error.
The `?` operator is valid only inside an error function.
When a `?` expression fails, the function returns the error.

```cinder
fn read_sensor() !u16 {
    return 42;
}

fn read_and_process() !u32 {
    let val = read_sensor()?;
    return val as u32 + 100;
}
```

The `else` clause unwraps an error result.
The `else` block runs when the result is an error.

```cinder
let result = read_sensor() else {
    return 0;
};
// here result has type u16
```

---

## 15. unsafe and asm

### 15.1 unsafe

The `unsafe` block allows unsafe operations.
The compiler checks safety outside `unsafe`.

| Operation | outside `unsafe` | inside `unsafe` |
|-----------|------------------|-----------------|
| Constant array index out of bounds | error | allowed |
| Uninitialized variable | error | error |
| Pointer arithmetic | error | allowed |
| Dereference of a raw pointer | error | allowed |
| Inline assembly | error | allowed |
| Unsafe casts | error | allowed |

```cinder
unsafe {
    let reg = 0x40001000 as *u32;
    *reg = 0xDEADBEEF;
    let p = (0xB8000 + 0x14) as *u16;
    *p = 0x0F20;
    asm("wfi");
}
```

### 15.2 Inline Assembly

The `asm` expression runs inline assembly.
The `asm` expression requires an `unsafe` context.

```cinder
unsafe {
    asm("nop");
    asm("wfi");
    asm("hlt");
}
```

---

## 16. Modules

### 16.1 use

The `use` statement imports a module.
The path is a string.
The compiler resolves the path relative to the current file.
The compiler also searches the include directories.
The standard library directory is an include directory by default.

```cinder
use "std/io.cnd";
use "drivers/gpio.cnd";
```

The path must end with the file extension.

### 16.2 export

A declaration is private by default.
The keyword `export` makes a declaration public.

```cinder
export fn uart_init(base: usize, baud: u32) -> Uart {
    return Uart { base: base, baud: baud };
}

export struct Uart {
    base: usize;
    baud: u32;
}
```

The keyword `export` works on functions, structs, enums, constants, statics, and external functions.

### 16.3 Target Filter

The attribute `#[target("...")]` filters a declaration by target.
A declaration runs only on the named target.
The known targets are `x86_64` and `x86_64-freestanding`.

```cinder
#[target("x86_64")]
fn x86_specific() { }

#[target("x86_64-freestanding")]
fn freestanding_specific() { }
```

---

## 17. Command Line

The compiler is the script `main.rb`.
The script `cinder` runs `main.rb`.

### 17.1 Commands

| Command | Action |
|---------|--------|
| `check <file>` | lex, parse, load modules, run static analysis |
| `build <file>` | check, then generate output |
| `tokens <file>` | print the token stream (debug) |
| `ast <file>` | print the AST (debug) |

### 17.2 Options

| Option | Meaning |
|--------|---------|
| `-I <dir>` | add a module search directory, repeatable |
| `--target=<arch>` | target architecture, default `x86_64` |
| `--emit=llvm\|asm\|obj\|bin\|kernel` | output format, default `llvm` |
| `--mode=debug\|release` | build mode, default `debug` |
| `--linker-script=<path>` | linker script for `--emit=kernel` |
| `--boot=<file.s>` | assembly boot stub for `--emit=kernel` |
| `--entry=<name>` | kernel entry symbol, default `_start` |
| `-o <file>` | output file name |
| `-v`, `--verbose` | keep intermediate files, print toolchain commands |
| `-h`, `--help` | print the help text |

### 17.3 Examples

```bash
# check a file
cinder check main.cnd

# generate LLVM IR
cinder build main.cnd --emit=llvm -o main.ll

# generate a native executable
cinder build main.cnd --emit=bin -o main

# generate a freestanding kernel image
cinder build main.cnd --target=x86_64-freestanding \
    --emit=kernel --linker-script=linker.ld --boot=boot.s -o kernel.bin
```

### 17.4 Build Modes

The mode `debug` is the default.
In debug mode, the compiler emits bounds checks.
The runtime traps when a check fails.

The mode `release` enables optimizations.
In release mode, the compiler omits the bounds checks.

### 17.5 Toolchain

The compiler needs these tools for `--emit=asm`, `obj`, `bin`, and `kernel`:

| Tool | Source |
|------|--------|
| `llc` | LLVM |
| `as`, `ld`, `objcopy` | binutils |
| `cc` | a C compiler, for `--emit=bin` only |

The compiler reports an error when a required tool is missing.

---

## 18. Standard Library

The standard library is small.
The standard library is optional.
A program imports the standard library with `use`.

```cinder
use "std/io.cnd";
use "std/x86.cnd";
```

The module `std/io.cnd` provides:

- `putchar`, `print`, `println`, `print_newline`
- `print_u32`, `print_i32`, `print_u64`, `print_i64`
- `print_cstr`, `puts`, `strlen`, `printf`, `fflush`
- `write`

The module `std/x86.cnd` provides port I/O:

- `outb`, `outw`, `outl`
- `inb`, `inw`, `inl`

---

## 19. Glossary

| Term | Meaning |
|------|---------|
| array | a fixed-length sequence of values |
| cast | the change of a value from one type to another type |
| constant | a value computed at compile time |
| enum | a type with named variants |
| error type | the type `!T`, a value or an error |
| module | one source file |
| optional type | the type `?T`, a value or `none` |
| pointer | a value that stores an address |
| slice | a view into an array, a pointer and a length |
| static | a global variable with one instance |
| target | a machine architecture for code generation |
| unsafe | code with unchecked operations |

---

## 20. Cinder Compared to C

| Aspect | C | Cinder |
|--------|---|--------|
| Preprocessor | yes | no |
| Header files | yes | no |
| defer | no | yes |
| NULL | yes | `?T` optional types |
| errno | yes | `!T` error types |
| Safe strings | no | `[]u8` |
| Explicit unsafe | no | yes |
| Macros | yes | no |
| Generics | no | no |
