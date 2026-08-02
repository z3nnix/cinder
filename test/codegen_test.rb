require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/error_reporter"
require_relative "../lib/lexer"
require_relative "../lib/ast"
require_relative "../lib/parser"
require_relative "../lib/loader"
require_relative "../lib/sema"
require_relative "../lib/targets"
require_relative "../lib/codegen"

class CodegenTest < Minitest::Test
  include Cinder
  include Cinder::AST

  TOOLS = %w[llvm-as llc as cc].select { |t| system("command -v #{t} >/dev/null 2>&1") }

  def setup
    @tmp = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def build(src, mode: :debug)
    file = File.join(@tmp, "main.cnd")
    File.write(file, src)
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: [], reporter: reporter) { |p| File.read(p) }
    program = loader.load(file)
    return [reporter, nil] unless reporter.diagnostics.empty?
    sema = Sema.new(program, reporter)
    sema.check
    return [reporter, nil] unless reporter.diagnostics.empty?
    [reporter, Codegen.new(program, sema, mode: mode).generate]
  end

  def gen_ok(src, mode: :debug)
    reporter, ir = build(src, mode: mode)
    assert_empty reporter.diagnostics.map(&:to_s)
    ir
  end

  def run_exit(src)
    file = File.join(@tmp, "main.cnd")
    File.write(file, src)
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: [], reporter: reporter) { |p| File.read(p) }
    program = loader.load(file)
    sema = Sema.new(program, reporter)
    sema.check
    assert_empty reporter.diagnostics.map(&:to_s)
    ir = Codegen.new(program, sema).generate
    ll = File.join(@tmp, "main.ll")
    asm = File.join(@tmp, "main.s")
    obj = File.join(@tmp, "main.o")
    bin = File.join(@tmp, "main")
    File.write(ll, ir)
    assert system("llc", "-O", "0", "-filetype=asm", ll, "-o", asm), "llc failed:\n#{ir}"
    assert system("as", asm, "-o", obj), "as failed:\n#{ir}"
    assert system("cc", "-no-pie", obj, "-o", bin), "cc failed:\n#{ir}"
    out, _err, st = Open3.capture3(bin)
    st.exitstatus
  end

  def assert_ir_includes(ir, *fragments)
    fragments.each { |f| assert_includes ir, f, "missing fragment #{f.inspect} in IR:\n#{ir}" }
  end

  def test_simple_arith
    ir = gen_ok("fn main() -> i32 { return 2 + 3 * 4; }")
    assert_ir_includes ir,
      "define i32 @cinder_main()",
      "define i32 @main()"
  end

  def test_trailing_commas
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 0, run_exit(<<~CND)
      struct P {
          x: i32,
          y: i32,
      }

      fn sum(a: i32, b: i32,) -> i32 { return a + b; }

      fn main() -> i32 {
          let p = P { x: 1, y: 2, };
          let arr = [1, 2, 3,];
          let s = sum(4, 5,);
          if p.x == 1 && p.y == 2 && arr[2] == 3 && s == 9 { return 0; }
          return 1;
      }
    CND
  end

  def test_ir_is_valid
    skip "llvm-as not available" unless TOOLS.include?("llvm-as")
    ir = gen_ok(<<~CND)
      fn add(a: i32, b: i32) -> i32 { return a + b; }
      fn main() { let x = add(1, 2); }
    CND
    ll = File.join(@tmp, "main.ll")
    File.write(ll, ir)
    assert system("llvm-as", ll, "-o", "#{ll}.bc"), "invalid IR:\n#{ir}"
  end

  def test_fib
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 88, run_exit(<<~CND)
      fn fib(n: i32) -> i32 {
          if n < 2 { return n; }
          return fib(n - 1) + fib(n - 2);
      }
      fn main() -> i32 {
          let mut sum = 0;
          for i in 0..10 { sum += fib(i); }
          return sum;
      }
    CND
  end

  def test_for_inclusive
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal(-5, run_exit(<<~CND).then { |v| v > 128 ? v - 256 : v })
      fn main() -> i32 {
          let mut a = 0;
          for i in 0..5 { a += i; }
          for i in 0..=5 { a -= i; }
          return a;
      }
    CND
  end

  def test_struct_enum_switch
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 123, run_exit(<<~CND)
      enum Color { Red; Green; Blue; }
      struct Point { x: i32; y: i32; }
      fn area(p: Point) -> i32 { return p.x * p.y; }
      fn score(c: Color) -> i32 {
          switch c {
              Color.Red => { return 1; }
              .Green => { return 10; }
              else => { return 100; }
          }
      }
      fn main() -> i32 {
          let p = Point { x: 3, y: 4 };
          return area(p) + score(Color.Red) + score(Color.Green) + score(Color.Blue);
      }
    CND
  end

  def test_switch_int_ranges
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 225, run_exit(<<~CND)
      fn classify(v: i32) -> i32 {
          switch v {
              0 => { return 5; }
              1..4 => { return 20; }
              else => { return 200; }
          }
      }
      fn main() -> i32 {
          return classify(0) + classify(3) + classify(99);
      }
    CND
  end

  def test_maybe_else
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 41, run_exit(<<~CND)
      fn maybe_inc(v: ?i32) -> i32 {
          let x = v else { return -1; };
          return x + 1;
      }
      fn main() -> i32 {
          return maybe_inc(41) + maybe_inc(none);
      }
    CND
  end

  def test_error_unwrap
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 14, run_exit(<<~CND)
      enum Err { E1; E2; }
      fn may_fail(fail: bool) !i32 {
          if fail { return Err.E2; }
          return 7;
      }
      fn use_it(fail: bool) !i32 {
          let v = may_fail(fail)?;
          return v * 2;
      }
      fn main() -> i32 {
          let a = use_it(false) else { return -1; };
          let b = use_it(true) else { return a; };
          return b;
      }
    CND
  end

  def test_while_break_continue_loop
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 17, run_exit(<<~CND)
      fn main() -> i32 {
          let mut i = 0;
          let mut acc = 0;
          while i < 10 {
              i += 1;
              if i % 2 == 0 { continue; }
              if i > 7 { break; }
              acc += i;
          }
          loop {
              acc += 1;
              break;
          }
          return acc;
      }
    CND
  end

  def test_elif_chain_unique_labels
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 10, run_exit(<<~CND)
      fn classify(v: i32) -> i32 {
          if v == 0 { return 1; }
          else if v == 1 { return 2; }
          else if v == 2 { return 3; }
          else { return 4; }
      }
      fn main() -> i32 {
          return classify(0) + classify(1) + classify(2) + classify(9);
      }
    CND
  end

  def test_bitwise_ops
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 0, run_exit(<<~CND)
      fn main() -> i32 {
          let a: u16 = 0xF23C;
          let x: u32 = ((a >> 12) & 0xF) as u32;
          let y: u32 = ((a >> 8) & 0xF) as u32;
          let z: u32 = ((a as u8) | 0x00) as u32;
          let w: u32 = ((a as u8) ^ 0xFF) as u32;
          if x != 0xF { return 1; }
          if y != 0x2 { return 2; }
          if z != 0x3C { return 3; }
          if w != 0xC3 { return 4; }
          return 0;
      }
    CND
  end

  def test_defer_lifo
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 49, run_exit(<<~CND)
      fn run(buf: []i32) -> i32 {
          buf[0] = 1;
          defer buf[1] = 2;
          defer buf[2] = 3;
          return 99;
      }
      fn main() -> i32 {
          let b = [0, 0, 0];
          let r = run(b[..]);
          return b[0] * 1000 + b[1] * 100 + b[2] * 10 + r;
      }
    CND
  end

  def test_strings_and_pointers
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 147, run_exit(<<~CND)
      fn string_len(s: []u8) -> i32 { return s.len as i32; }
      fn bump(p: *i32) -> i32 {
          unsafe {
              *p += 10;
              return *p;
          }
      }
      fn max(a: i32, b: i32) -> i32 {
          let m = if a > b { a } else { b };
          return m;
      }
      fn main() -> i32 {
          let s = "hello";
          let l = string_len(s);
          let mut v = 5;
          let r = bump(&v);
          let m = max(3, 9);
          return l * 100 + r * 10 + m;
      }
    CND
  end

  def test_floats
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 5, run_exit(<<~CND)
      fn avg(a: f64, b: f64) -> f64 {
          return (a + b) / 2.0;
      }
      fn main() -> i32 {
          let x = avg(3.0, 7.0);
          return x as i32;
      }
    CND
  end

  def test_debug_mode_traps_oob
    skip "llvm-as not available" unless TOOLS.include?("llvm-as")
    ir = gen_ok(<<~CND, mode: :debug)
      fn main() {
          let a = [1, 2, 3];
          let i = 5;
          let x = a[i];
      }
    CND
    assert_ir_includes ir, "@llvm.trap", "unreachable"
  end

  def test_release_mode_no_trap
    ir = gen_ok(<<~CND, mode: :release)
      fn main() {
          let a = [1, 2, 3];
          let x = a[1];
      }
    CND
    refute_includes ir, "@llvm.trap"
  end

  def test_static_global
    ir = gen_ok(<<~CND)
      static counter: i32 = 42;
      fn main() -> i32 { return counter; }
    CND
    assert_ir_includes ir, "@cinder_static.counter = global i32 42"
  end

  def test_target_freestanding_triple
    file = File.join(@tmp, "main.cnd")
    File.write(file, <<~CND)
      fn main() -> i32 { return 0; }
    CND
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: [], reporter: reporter) { |p| File.read(p) }
    program = loader.load(file)
    sema = Sema.new(program, reporter, target: "x86_64-freestanding")
    sema.check
    assert_empty reporter.diagnostics.map(&:to_s)
    ir = Codegen.new(program, sema, target: "x86_64-freestanding").generate
    assert_includes ir, 'target triple = "x86_64-unknown-none-elf"'
    assert_includes ir, "target datalayout"
  end

  def test_target_host_triple_default
    ir = gen_ok("fn main() -> i32 { return 0; }")
    assert_includes ir, 'target triple = "x86_64-pc-linux-gnu"'
  end

  def test_volatile_load_store
    ir = gen_ok(<<~CND)
      fn main() {
          let mut a: u32 = 0;
          let p: *volatile u32 = &a as *volatile u32;
          unsafe {
              *p = 42;
              let y = *p;
              p[0] = 7;
              let z = p[0];
          }
      }
    CND
    assert_ir_includes ir, "load volatile i32", "store volatile i32"
  end

  def test_volatile_field_access
    ir = gen_ok(<<~CND)
      struct Reg { val: u32; }
      fn main() {
          let mut r: Reg = Reg { val: 0 };
          let p: *volatile Reg = &r as *volatile Reg;
          unsafe {
              p.val = 1;
              let v = p.val;
          }
      }
    CND
    assert_ir_includes ir, "load volatile i32", "store volatile i32"
  end

  def test_volatile_run
    assert_equal 42, run_exit(<<~CND)
      fn main() -> i32 {
          let mut a: u32 = 0;
          let p: *volatile u32 = &a as *volatile u32;
          unsafe {
              *p = 42;
              return *p as i32;
          }
      }
    CND
  end

  def test_static_section_ir
    ir = gen_ok(<<~CND)
      static mb_header: [3]u32 = [0x1BADB002, 0, 0xE4524FFE] section(".multiboot");
      fn main() -> i32 { return 0; }
    CND
    assert_ir_includes ir, '@cinder_static.mb_header = global [3 x i32] [i32 464367618, i32 0, i32 3830599678], section ".multiboot"'
  end

  def test_noreturn_ir
    ir = gen_ok(<<~CND)
      fn panic() noreturn { loop { } }
      fn main() -> i32 { return 0; }
    CND
    assert_ir_includes ir, 'define void @cinder_panic()', "noreturn"
  end

  def test_port_io_intrinsics
    ir = gen_ok(<<~CND)
      export extern fn outb(port: u16, value: u8);
      export extern fn inb(port: u16) -> u8;
      fn main() -> i32 {
          unsafe {
              outb(0x3F8, 65);
              let v = inb(0x3F9);
              return v as i32;
          }
      }
    CND
    assert_ir_includes ir,
      "outb %al, %dx",
      "inb %dx, %al",
      '"{dx},{al}"',
      '"={al},{dx}"'
    refute_includes ir, "declare.*@outb"
    refute_includes ir, "declare.*@inb"
  end

  def test_port_io_is_valid
    skip "llvm-as not available" unless TOOLS.include?("llvm-as")
    ir = gen_ok(<<~CND)
      export extern fn outb(port: u16, value: u8);
      export extern fn inb(port: u16) -> u8;
      fn main() -> i32 {
          unsafe {
              outb(0x3F8, 65);
              return inb(0x3F9) as i32;
          }
      }
    CND
    ll = File.join(@tmp, "main.ll")
    File.write(ll, ir)
    assert system("llvm-as", ll, "-o", "#{ll}.bc"), "invalid IR:\n#{ir}"
  end

  def test_const_casts_in_constants
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 49, run_exit(<<~CND)
      const FROM_FLOAT = 42.9 as i32;
      const FROM_INT = 7 as f64;
      fn main() -> i32 {
          return FROM_FLOAT + FROM_INT as i32;
      }
    CND
  end

  def test_u128_arithmetic
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 0, run_exit(<<~CND)
      const MAX_U128: u128 = 340282366920938463463374607431768211455;
      fn main() -> i32 {
          let a: u128 = MAX_U128;
          let b: u128 = a + 1;
          if b == 0 { return 0; }
          return 1;
      }
    CND
  end

  def test_i128_arithmetic
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    assert_equal 0, run_exit(<<~CND)
      const MAX_I128: i128 = 170141183460469231731687303715884105727;
      fn main() -> i32 {
          let a: i128 = MAX_I128;
          let b: i128 = a - 1;
          let c: i128 = 0 - 1;
          if b == 170141183460469231731687303715884105726 && c == -1 { return 0; }
          return 1;
      }
    CND
  end
end
