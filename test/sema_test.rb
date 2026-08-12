require "minitest/autorun"
require "tmpdir"
require_relative "../lib/error_reporter"
require_relative "../lib/lexer"
require_relative "../lib/ast"
require_relative "../lib/parser"
require_relative "../lib/loader"
require_relative "../lib/sema"
require_relative "../lib/targets"

class SemaTest < Minitest::Test
  include Cinder
  include Cinder::AST

  def setup
    @tmp = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def write(name, content)
    full = File.join(@tmp, name)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def check(entry, include_dirs: [])
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: include_dirs, reporter: reporter) { |p| File.read(p) }
    program = loader.load(File.join(@tmp, entry))
    return reporter unless reporter.diagnostics.empty?
    Sema.new(program, reporter).check
    reporter
  end

  def ok(src)
    write("main.cnd", src)
    reporter = check("main.cnd")
    assert_empty reporter.diagnostics.map(&:to_s)
  end

  def err(src, pattern)
    write("main.cnd", src)
    reporter = check("main.cnd")
    refute_empty reporter.diagnostics, "expected an error matching #{pattern.inspect}"
    assert_match pattern, reporter.diagnostics.map(&:message).join("\n")
  end

  # positive 

  def test_empty_program
    ok("")
  end

  def test_simple_fn
    ok("fn add(a: i32, b: i32) -> i32 { return a + b; }")
  end

  def test_implicit_return
    ok("fn mul(a: i32, b: i32) -> i32 { a * b }")
  end

  def test_let_inference
    ok("fn f() { let x = 42; let y = 3.14; let c = 'A'; let b = true; }")
  end

  def test_type_annotation_adaptation
    ok("fn f() { let a: u32 = 42; let b: u64 = 100; let f: f64 = 3; let c: u8 = 'A'; }")
  end

  def test_let_mut_and_assign
    ok("fn f() { let mut x = 0; x += 1; x = 5; }")
  end

  def test_shadowing
    ok("fn f() { let x = 10; let x = x + 5; }")
  end

  def test_params_mutable
    ok("fn f(x: u32) { x = x + 1; }")
  end

  def test_static_read_write
    ok("static GLOBAL_COUNTER: u32 = 0; fn increment() { GLOBAL_COUNTER += 1; }")
  end

  def test_const_array_len
    ok("const N = 4; fn f() { let a: [N]u8 = [1, 2, 3, 4]; }")
  end

  def test_const_arithmetic
    ok("const W = 4; const H = 2; const TOTAL = W * H; fn f() { let a: [TOTAL]u8 = [1, 2, 3, 4, 5, 6, 7, 8]; }")
  end

  def test_optional_values
    ok(<<~CND)
      fn g() -> ?u32 { return none; }
      fn f() { let m: ?u32 = 42; let n: ?u32 = none; let o = g(); }
    CND
  end

  def test_maybe_else
    ok(<<~CND)
      fn get() -> ?u32 { return 42; }
      fn f() {
        let m = get() else { return; };
        let y: u32 = m;
      }
    CND
  end

  def test_error_unwrap
    ok(<<~CND)
      fn read() !u16 { return 1; }
      fn f() !u32 { let v = read()?; return v as u32 + 100; }
    CND
  end

  def test_error_return_enum_value
    ok(<<~CND)
      enum Error { Bad; }
      fn f() !u32 { return Error.Bad; }
    CND
  end

  def test_switch_int
    ok(<<~CND)
      fn f(v: i32) {
        switch v {
          0 => {}
          1..10 => {}
          42 => {}
          else => {}
        }
      }
    CND
  end

  def test_switch_enum
    ok(<<~CND)
      enum Color { Red; Green; Blue; }
      fn f(c: Color) {
        switch c {
          Color.Red => {}
          .Green => {}
          else => {}
        }
      }
    CND
  end

  def test_for_range
    ok("fn work(i: i32) { } fn f() { for i in 0..10 { work(i); } }")
  end

  def test_for_inclusive_range
    ok("fn work(i: i32) { } fn f() { for i in 0..=5 { work(i); } }")
  end

  def test_for_iter
    ok("fn use_it(v: i32) { } fn f(a: [3]i32) { for value in a { use_it(value); } }")
  end

  def test_for_iter_with_index
    ok("fn use_it(i: usize, v: i32) { } fn f(a: [3]i32) { for i, value in a { use_it(i, value); } }")
  end

  def test_for_over_slice
    ok("fn use_it(v: u8) { } fn f(data: []u8) { for value in data { use_it(value); } }")
  end

  def test_while_and_loop
    ok(<<~CND)
      fn f() {
        let mut i = 0;
        while i < 10 { i += 1; }
        loop { break; }
        loop { continue; }
      }
    CND
  end

  def test_struct_init_and_fields
    ok(<<~CND)
      struct Point { x: i32; y: i32; }
      fn f() {
        let p = Point { x: 1, y: 2 };
        let q = p.x + p.y;
        let mut p2 = p;
        p2.x = 3;
      }
    CND
  end

  def test_struct_shorthand
    ok(<<~CND)
      struct Uart { base: usize; baud: u32; }
      fn uart_init(base: usize, baud: u32) -> Uart { return Uart { base, baud }; }
    CND
  end

  def test_nested_struct_field
    ok(<<~CND)
      struct A { b: B; }
      struct B { c: i32; }
      fn f(a: A) -> i32 { return a.b.c; }
    CND
  end

  def test_field_through_pointer
    ok(<<~CND)
      struct PwmTimer { timer: Timer; duty: u8; }
      struct Timer { counter: u32; }
      fn pwm_start(pwm: *PwmTimer) { pwm.timer.counter = 0; }
    CND
  end

  def test_slice_operations
    ok(<<~CND)
      fn f(arr: [4]u8) {
        let a = arr[0..2];
        let b = arr[1..];
        let c = arr[..3];
        let d = arr[..];
        let e = arr[0];
      }
    CND
  end

  def test_slice_len
    ok("fn len_of(data: []u8) -> usize { return data.len; }")
  end

  def test_array_literal_inference
    ok("fn f() { let a = [10, 20, 30, 40]; }")
  end

  def test_array_annotation
    ok("fn f() { let a: [4]u8 = [10, 20, 30, 40]; }")
  end

  def test_strings
    ok("fn f() { let s = \"Hello\"; let c = c\"Hi\\0\"; let d = b\"raw\"; }")
  end

  def test_string_passed_to_slice_param
    ok("fn log(msg: []u8) { } fn f() { log(\"Hello\"); }")
  end

  def test_unsafe_block
    ok(<<~CND)
      fn f() {
        unsafe {
          let p = 0x40001000 as *u32;
          *p = 0xDEADBEEF;
          asm("wfi");
        }
      }
    CND
  end

  def test_unsafe_fn
    ok(<<~CND)
      unsafe fn dangerous() {
        let p = 0x40001000 as *u32;
        *p = 0x01;
      }
      fn f() { unsafe { dangerous(); } }
    CND
  end

  def test_unsafe_block_scopes_variables
    err(<<~CND, /undefined variable `command`/)
      fn f(p: *u8) {
        unsafe {
          let command: []u8 = p[..0];
        }
        if command.len > 0 {
        }
      }
    CND
  end

  def test_if_body_scopes_variables
    err(<<~CND, /undefined variable `x`/)
      fn f(a: bool) {
        if a { let x = 1; }
        if x > 0 { }
      }
    CND
  end

  def test_while_body_scopes_variables
    err(<<~CND, /undefined variable `i`/)
      fn f(n: i32) {
        while n > 0 {
          let i = 1;
          n -= 1;
        }
        let y: i32 = i;
      }
    CND
  end

  def test_address_of
    ok("fn f(x: u32) { let p: *u32 = &x; }")
  end

  def test_pointer_compare_null
    ok(<<~CND)
      fn alloc(n: u32) -> *u32 { null }
      fn free(p: *u32) { }
      fn f() {
        let ptr = alloc(1024);
        if ptr != null { free(ptr); }
      }
    CND
  end

  def test_if_expr
    ok("fn max(a: i32, b: i32) -> i32 { let m = if a > b { a } else { b }; return m; }")
  end

  def test_enum_value
    ok("enum Color { Red; Green; } fn f() { let c = Color.Red; }")
  end

  def test_lossless_widening
    ok("fn f() { let x: u8 = 1; let y: u32 = x; let z: usize = x; }")
  end

  def test_defer
    ok(<<~CND)
      fn alloc(n: u32) -> *u32 { null }
      fn free(p: *u32) { }
      fn f() {
        let ptr = alloc(1024);
        defer free(ptr);
        defer if ptr != null { free(ptr); };
      }
    CND
  end

  def test_call_forward_reference
    ok("fn a() { b(); } fn b() { }")
  end

  def test_multi_module_exported
    write("uart.cnd", "export fn uart_init() { }\nexport struct Uart { base: usize; }\n")
    write("main.cnd", <<~CND)
      use "uart.cnd";
      fn main() -> usize {
        uart_init();
        let u = Uart { base: 1 };
        return u.base;
      }
    CND
    assert_empty check("main.cnd").diagnostics
  end

  def test_full_spec_example
    src = File.join(__dir__, "..", "examples", "hello", "main.cnd")
    File.write(File.join(@tmp, "main.cnd"), File.read(src))
    reporter = check("main.cnd", include_dirs: [File.join(__dir__, "..", "lib")])
    assert_empty reporter.diagnostics.map(&:to_s)
  end

  # ---------- negative ----------

  def test_undefined_variable
    err("fn f() { x = 1; }", /undefined variable `x`/)
  end

  def test_assign_immutable
    err("fn f() { let x = 1; x = 2; }", /not mutable/)
  end

  def test_type_mismatch
    err("fn f() { let x: u32 = 1.5; }", /type mismatch/)
  end

  def test_float_to_int_strict
    err("fn f() { let x: i32 = 1.5; }", /type mismatch/)
  end

  def test_narrowing_errored
    err("fn g() -> u32 { 300 } fn f() { let x: u8 = g(); }", /type mismatch/)
  end

  def test_missing_struct_field
    err("struct P { x: i32; y: i32; } fn f() { let p = P { x: 1 }; }", /missing field `y`/)
  end

  def test_unknown_struct_field
    err("struct P { x: i32; } fn f() { let p = P { x: 1, z: 2 }; }", /no field `z`/)
  end

  def test_duplicate_struct_field
    err("struct P { x: i32; x: u8; }", /duplicate field `x`/)
  end

  def test_duplicate_enum_variant
    err("enum E { A; A; }", /duplicate variant `A`/)
  end

  def test_unknown_struct
    err("fn f() { let x = Nope { a: 1 }; }", /unknown struct `Nope`/)
  end

  def test_wrong_arg_count
    err("fn f(a: i32) { } fn g() { f(1, 2); }", /expects 1 argument/)
  end

  def test_unknown_function
    err("fn f() { nope(); }", /unknown function `nope`/)
  end

  def test_deref_outside_unsafe
    err("fn f(p: *u32) { *p = 1; }", /unsafe block/)
  end

  def test_asm_outside_unsafe
    err("fn f() { asm(\"wfi\"); }", /unsafe block/)
  end

  def test_call_unsafe_fn_outside_unsafe
    err("unsafe fn d() { } fn f() { d(); }", /requires an unsafe block/)
  end

  def test_pointer_index_outside_unsafe
    err("fn f(p: *u32) { let x = p[0]; }", /pointer indexing/)
  end

  def test_pointer_arith_outside_unsafe
    err("fn f(p: *u32) { let x = p + 1; }", /pointer arithmetic/)
  end

  def test_cast_ptr_outside_unsafe
    err("fn f() { let p = 0x1000 as *u32; }", /requires an unsafe block/)
  end

  def test_break_outside_loop
    err("fn f() { break; }", /outside of a loop/)
  end

  def test_continue_outside_loop
    err("fn f() { continue; }", /outside of a loop/)
  end

  def test_unwrap_outside_error_fn
    err("fn g() !i32 { return 1; } fn f() { let x = g()?; }", /error type/)
  end

  def test_unwrap_non_error_value
    err("fn f() !i32 { let x = 5; let y = x?; return y; }", /cannot unwrap/)
  end

  def test_array_out_of_bounds
    err("fn f() { let a = [1, 2, 3]; let x = a[5]; }", /out of bounds \(length 3\)/)
  end

  def test_slice_bound_out_of_bounds
    err("fn f() { let a = [1, 2, 3]; let x = a[0..4]; }", /out of bounds/)
  end

  def test_maybe_else_no_diverge
    err("fn work() { } fn f() { let m: ?u32 = none; let v = m else { work(); }; }", /must diverge/)
  end

  def test_optional_use_without_unwrap
    err("fn f() { let m: ?u32 = none; let x: u32 = m; }", /type mismatch/)
  end

  def test_maybe_else_on_non_optional
    err("fn f() { let x = 5; let y = x else { return 0; }; }", /optional or error/)
  end

  def test_range_pattern_on_enum
    err("enum C { A; } fn f(c: C) { switch c { 1..10 => {} } }", /range patterns/)
  end

  def test_enum_pattern_on_int
    err("fn f(v: i32) { switch v { .A => {} } }", /enum subject/)
  end

  def test_duplicate_switch_case
    err("fn f(v: i32) { switch v { 1 => {} 1 => {} } }", /duplicate switch case/)
  end

  def test_empty_array_literal
    err("fn f() { let a = []; }", /empty array literal/)
  end

  def test_array_repeat_literal
    ok("fn f() { let a: [4]i32 = [0; 4]; let b: [8]u8 = [0; 8]; let c = [7; 3]; }")
    ok("fn g() { let z = [0; 0]; }")
  end

  def test_array_repeat_length_mismatch
    err("fn f() { let a: [4]i32 = [0; 3]; }", /has 3 element\(s\), expected 4/)
  end

  def test_array_repeat_type_mismatch
    err("fn f() { let a: [4]u8 = [300; 4]; }", /does not fit in u8/)
  end

  def test_array_repeat_bad_count
    err("fn f() { let a = [0; x]; }", /invalid array length/)
    err("fn f() { let a = [0; -1]; }", /non-negative/)
    err("fn f() { let a = [0; 1.5]; }", /must be an integer/)
  end

  def test_void_value_use
    err("fn f() { } fn g() { let x = f(); }", /void value/)
  end

  def test_return_value_in_void
    err("fn f() { return 1; }", /cannot return a value/)
  end

  def test_trailing_expr_in_void
    err("fn f() { 1 + 1 }", /void function cannot return/)
  end

  def test_implicit_return_mismatch
    err("fn f() -> u32 { 1.5 }", /implicit return/)
  end

  def test_static_nonconst_init
    err("fn g() { } static X: u32 = g();", /static initializer/)
  end

  def test_duplicate_top_level
    err("fn f() { } fn f() { }", /duplicate definition of `f`/)
  end

  def test_unknown_type
    err("fn f(a: Nope) { }", /unknown type `Nope`/)
  end

  def test_circular_const
    err("const A = B; const B = A;", /circular constant/)
  end

  def test_if_condition_must_be_bool
    err("fn f(x: i32) { if x { } }", /must be bool/)
  end

  def test_field_on_integer
    err("fn f(x: i32) { let y = x.field; }", /cannot access field/)
  end

  def test_private_fn_cross_module
    write("uart.cnd", "fn priv_fn() { }\nexport fn pub_fn() { }\n")
    write("main.cnd", "use \"uart.cnd\";\nfn main() { priv_fn(); }\n")
    reporter = check("main.cnd")
    assert_match(/private to its module/, reporter.diagnostics.map(&:message).join("\n"))
  end

  def test_private_struct_cross_module
    write("uart.cnd", "struct Uart { base: usize; }\nexport fn mk() -> Uart { Uart { base: 1 } }\n")
    write("main.cnd", "use \"uart.cnd\";\nfn main() { let u = Uart { base: 1 }; }\n")
    reporter = check("main.cnd")
    assert_match(/private to its module/, reporter.diagnostics.map(&:message).join("\n"))
  end

  # ---------- volatile pointers ----------

  def test_volatile_pointer_type_ok
    ok("fn f(p: *volatile u32) { }\nfn g(p: *const volatile u16) { }")
  end

  def test_volatile_pointer_mismatch
    err(<<~CND, /\*volatile u32/)
      fn main() {
          let mut a: u32 = 0;
          let p: *u32 = &a;
          let vp: *volatile u32 = p;
      }
    CND
  end

  def test_volatile_pointer_cast_ok
    ok(<<~CND)
      fn main() {
          let mut a: u32 = 0;
          let p: *u32 = &a;
          let vp: *volatile u32 = p as *volatile u32;
      }
    CND
  end

  def test_volatile_pointer_no_slice
    err(<<~CND, /cannot slice a volatile pointer/)
      fn main() {
          let mut a: u32 = 0;
          let vp: *volatile u32 = &a as *volatile u32;
          unsafe { let s = vp[0..2]; }
      }
    CND
  end

  # ---------- literal bounds ----------

  def test_int_literal_fits_in_annotated_type
    ok("fn f() { let a: u8 = 255; let b: u16 = 65535; let c: i8 = -128; let d: i8 = 127; }")
  end

  def test_u128_literal_bounds
    ok("fn f() { let a: u128 = 340282366920938463463374607431768211455; }")
    err("fn f() { let a: u128 = 340282366920938463463374607431768211456; }", /does not fit in u128/)
  end

  def test_i128_literal_bounds
    ok("fn f() { let a: i128 = 170141183460469231731687303715884105727; }")
    err("fn f() { let a: i128 = 170141183460469231731687303715884105728; }", /does not fit in i128/)
  end

  def test_typed_const_with_large_literal
    ok("const MAX_U128: u128 = 340282366920938463463374607431768211455; fn f() {}")
    ok("const MAX_I128: i128 = 170141183460469231731687303715884105727; fn f() {}")
    err("const BIG: u8 = 300; fn f() {}", /integer literal 300 does not fit in u8/)
    err("const NEG: u8 = -1; fn f() {}", /does not fit in u8/)
  end

  def test_typed_static_with_large_literal
    ok("static BIG: u128 = 340282366920938463463374607431768211455; fn f() {}")
    err("static BIG: u8 = 300; fn f() {}", /integer literal 300 does not fit in u8/)
  end

  def test_negated_literal_in_mixed_int_compare
    ok("fn f() { let a: i128 = 0 - 1; if a == -1 { } }")
    ok("fn f() { let a: i64 = 0 - 1; if a < -1 { } }")
  end

  def test_int_literal_overflow_u8
    err("fn f() { let a: u8 = 300; }", /integer literal 300 does not fit in u8/)
  end

  def test_negative_literal_into_unsigned
    err("fn f() { let a: u8 = -1; }", /does not fit in u8/)
  end

  def test_negative_literal_fits_signed
    ok("fn f() { let a: i16 = -300; }")
  end

  def test_suffixed_literal_overflow
    err("fn f() { let a: u8 = 300u8; }", /does not fit in u8/)
  end

  def test_literal_overflow_optional
    err("fn f() { let a: ?u8 = 300; }", /does not fit in u8/)
  end

  # ---------- aggregate comparison ----------

  def test_struct_comparison_rejected
    err("struct P { x: i32; } fn f() { let a = P { x: 1 }; let b = P { x: 1 }; let c = a == b; }", /cannot compare P and P/)
  end

  def test_array_comparison_rejected
    err("fn f() { let a = [1, 2]; let b = [1, 2]; let c = a != b; }", /cannot compare/)
  end

  def test_slice_comparison_rejected
    err("fn f(a: []u8, b: []u8) { let c = a == b; }", /cannot compare/)
  end

  def test_pointer_comparison_allowed
    ok("fn f(p: *u32, q: *u32) { let a = p == q; }")
  end

  def test_optional_comparison_allowed
    ok("fn f(a: ?u32, b: ?u32) { let c = a == b; }")
  end

  # ---------- const casts ----------

  def test_const_float_to_int_cast
    ok("const X = 1.5 as i32; fn f() -> i32 { return X; }")
  end

  def test_const_int_to_float_cast
    ok("const Y = 7 as f64; fn f() -> f64 { return Y; }")
  end

   

  def test_cast_away_volatile_requires_unsafe
    err(<<~CND, /requires an unsafe block/)
      fn main() {
          let mut a: u32 = 0;
          let p: *volatile u32 = &a as *volatile u32;
          let q: *u32 = p as *u32;
      }
    CND
  end

  def test_cast_away_const_requires_unsafe
    err(<<~CND, /requires an unsafe block/)
      fn main() {
          let mut a: u32 = 0;
          let p: *const u32 = &a;
          let q: *u32 = p as *u32;
      }
    CND
  end

  def test_cast_adds_qualifiers_without_unsafe
    ok(<<~CND)
      fn main() {
          let mut a: u32 = 0;
          let p: *u32 = &a;
          let vp: *volatile u32 = p as *volatile u32;
      }
    CND
  end

  def test_cast_away_qualifiers_in_unsafe
    ok(<<~CND)
      fn main() {
          let mut a: u32 = 0;
          let p: *volatile u32 = &a as *volatile u32;
          unsafe { let q: *u32 = p as *u32; }
      }
    CND
  end

   

  def test_cast_pointer_to_bool_rejected
    err("fn f() { unsafe { let p = 0 as *u32; let b = p as bool; } }", /unsupported cast from \*u32 to bool/)
  end

  def test_cast_int_to_bool_rejected
    err("fn f() { unsafe { let b = 5 as bool; } }", /unsupported cast/)
  end

  def test_cast_struct_to_int_rejected
    err("struct P { x: i32; } fn f() { let p = P { x: 1 }; unsafe { let i = p as i32; } }", /unsupported cast/)
  end

  def test_cast_pointer_between_types_allowed_in_unsafe
    ok("fn f() { unsafe { let p = 0 as *u32; let q = p as *u8; let a = q as u64; } }")
  end

  # ---------- target filtering ----------

  def test_target_filtered_fn_not_visible
    err(<<~CND, /unknown function `arm_only`/)
      #[target("aarch64")]
      fn arm_only() -> i32 { return 1; }
      fn main() -> i32 { return arm_only(); }
    CND
  end

  def test_same_name_per_target_no_conflict
    write("main.cnd", <<~CND)
      #[target("aarch64")]
      fn arch() -> i32 { return 64; }
      #[target("x86_64")]
      fn arch() -> i32 { return 86; }
      fn main() -> i32 { return arch(); }
    CND
    reporter = check("main.cnd")
    assert_empty reporter.diagnostics.map(&:to_s)
  end

  def test_target_filtered_type_not_visible
    err(<<~CND, /unknown struct `ArmOnly`/)
      #[target("aarch64")]
      struct ArmOnly { x: i32; }
      fn main() { let a = ArmOnly { x: 1 }; }
    CND
  end

  # ---------- function pointers ----------

  def test_fn_ptr_var_assign_and_call
    ok("fn add(a: i32, b: i32) -> i32 { return a + b; }\nfn main() { let f: fn(i32, i32) -> i32 = add; let r = f(1, 2); }")
  end

  def test_fn_ptr_addr_of
    ok("fn add(a: i32, b: i32) -> i32 { return a + b; }\nfn main() { let f: fn(i32, i32) -> i32 = &add; let r = f(1, 2); }")
  end

  def test_fn_ptr_param_indirect_call
    ok("fn apply(f: fn(i32) -> i32, x: i32) -> i32 { return f(x); }\nfn dbl(x: i32) -> i32 { return x * 2; }\nfn main() { let r = apply(dbl, 21); }")
  end

  def test_fn_ptr_void_return
    ok("fn greet() { }\nfn run(cb: fn()) { cb(); }\nfn main() { run(greet); }")
  end

  def test_fn_ptr_struct_field
    ok(<<~CND)
      struct H { id: i32; cb: fn(i32) -> i32; }
      fn dbl(x: i32) -> i32 { return x * 2; }
      fn invoke(h: struct H, v: i32) -> i32 { return h.cb(v); }
      fn main() { let h = H { id: 1, cb: dbl }; let r = invoke(h, 3); }
    CND
  end

  def test_fn_ptr_extern_param
    ok("extern fn atexit(cb: fn() -> void) -> i32;\nfn bye() { }\nfn main() { let r = atexit(bye); }")
  end

  def test_fn_ptr_null
    ok("fn dbl(x: i32) -> i32 { return x * 2; }\nfn main() { let f: fn(i32) -> i32 = null; if f != null { } }")
  end

  def test_fn_ptr_arg_type_mismatch
    err("fn dbl(x: i32) -> i32 { return x * 2; }\nfn main() { let f: fn(i32) -> i32 = dbl; f(c\"s\"); }", /type mismatch for parameter/)
  end

  def test_fn_ptr_arity_mismatch
    err("fn dbl(x: i32) -> i32 { return x * 2; }\nfn main() { let f: fn(i32) -> i32 = dbl; f(1, 2); }", /expects 1 argument/)
  end

  def test_fn_ptr_struct_mismatch
    err("fn dbl(x: i32) -> i32 { return x * 2; }\nfn main() { let f: fn(i64) -> i32 = dbl; }", /expected fn\(i64\)/)
  end

  def test_cannot_compare_fn_ptrs_to_int
    err("fn dbl(x: i32) -> i32 { return x * 2; }\nfn main() { let f: fn(i32) -> i32 = dbl; if f == 0 { } }", /cannot compare/)
  end

  # ---------- void pointers ----------

  def test_void_ptr_coerce_from_typed
    ok("extern fn memset(dst: *void, c: i32, n: usize) -> *void;\nfn main() { let mut x: u64 = 1; memset(&x, 0, 8); }")
  end

  def test_void_ptr_cast_to_typed_requires_unsafe
    err("extern fn malloc(n: usize) -> *void;\nfn main() { let p: *void = malloc(8); let q: *i32 = p as *i32; }", /requires an unsafe block/)
  end

  def test_void_ptr_cast_to_typed_in_unsafe
    ok("extern fn malloc(n: usize) -> *void;\nfn main() { let p: *void = malloc(8); unsafe { let q: *i32 = p as *i32; } }")
  end

  def test_void_ptr_typecast_to_fn_unsupported
    err("extern fn malloc(n: usize) -> *void;\nfn main() { let p: *void = malloc(8); unsafe { let q: fn() -> i32 = p as fn() -> i32; } }", /unsupported cast/)
  end

  def test_deref_void_ptr_rejected
    err("fn main() { let p: *void = null; unsafe { let v = *p; } }", /cannot dereference a void pointer/)
  end

  def test_index_void_ptr_rejected
    err("fn main() { let p: *void = null; unsafe { let v = p[0]; } }", /cannot index a void pointer/)
  end

  def test_slice_void_ptr_rejected
    err("fn main() { let p: *void = null; unsafe { let s = p[0..2]; } }", /cannot slice a void pointer/)
  end

  def test_null_assignable_to_void_ptr
    ok("fn main() { let p: *void = null; if p != null { } }")
  end

  # ---------- sizeof / alignof / offsetof ----------

  def test_sizeof_primitive
    ok("fn main() { let s: usize = sizeof(i32); }")
  end

  def test_sizeof_struct
    ok(<<~CND)
      struct Pair { a: i32; b: u8; }
      fn main() { let s: usize = sizeof(struct Pair); }
    CND
  end

  def test_offsetof_struct_field
    ok(<<~CND)
      struct Pair { a: i32; b: u8; }
      fn main() { let o: usize = offsetof(struct Pair, b); }
    CND
  end

  def test_alignof_struct
    ok(<<~CND)
      struct Pair { a: i32; b: u8; }
      fn main() { let a: usize = alignof(struct Pair); }
    CND
  end

  def test_offsetof_unknown_field_error
    err("struct Pair { a: i32; b: u8; }\nfn main() { let o: usize = offsetof(struct Pair, z); }", /no field `z`/)
  end

  def test_offsetof_non_struct_error
    err("fn main() { let o: usize = offsetof(i32, z); }", /requires a struct type/)
  end

  def test_static_assert_ok
    ok(<<~CND)
      struct Pair { a: i32; b: u8; }
      static_assert(sizeof(i32) == 4);
      static_assert(sizeof(struct Pair) == 8);
      static_assert(offsetof(struct Pair, b) == 4);
      static_assert(alignof(i64) == 8);
      fn main() { }
    CND
  end

  def test_static_assert_failure
    err("struct Pair { a: i32; b: u8; }\nstatic_assert(sizeof(struct Pair) == 4);\nfn main() { }", /static_assert failed/)
  end

  def test_static_assert_non_const_error
    err("fn main() { }\nstatic_assert(main);", /requires a constant expression/)
  end

  def test_static_assert_in_function_body
    ok("fn main() { static_assert(sizeof(i32) == 4); }")
  end

  def test_sizeof_in_const
    ok("struct Pair { a: i32; b: u8; }\nconst SZ: usize = sizeof(struct Pair);\nfn main() { let s = SZ; }")
  end
end
