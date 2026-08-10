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

class ExternTest < Minitest::Test
  include Cinder
  include Cinder::AST

  ROOT = File.expand_path("..", __dir__)
  TOOLS = %w[llc as cc].select { |t| system("command -v #{t} >/dev/null 2>&1") }

  def setup
    @tmp = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def check(src)
    file = File.join(@tmp, "main.cnd")
    File.write(file, src)
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: [File.join(ROOT, "lib")], reporter: reporter) { |p| File.read(p) }
    program = loader.load(file)
    sema = Sema.new(program, reporter)
    sema.check
    reporter
  end

  def gen_ok(src)
    file = File.join(@tmp, "main.cnd")
    File.write(file, src)
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: [File.join(ROOT, "lib")], reporter: reporter) { |p| File.read(p) }
    program = loader.load(file)
    sema = Sema.new(program, reporter)
    sema.check
    assert_empty reporter.diagnostics.map(&:to_s)
    Codegen.new(program, sema).generate
  end

  def run_stdout(src)
    skip "toolchain not available" unless TOOLS.length == 3
    file = File.join(@tmp, "main.cnd")
    File.write(file, src)
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: [File.join(ROOT, "lib")], reporter: reporter) { |p| File.read(p) }
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
    [out, st.exitstatus]
  end

  # sema 

  def test_extern_declaration_needs_no_body
    r = check("extern fn write(fd: i32, buf: *u8, count: usize) -> isize;\nfn main() -> i32 { return 0; }\n")
    assert_empty r.diagnostics.map(&:to_s)
  end

  def test_extern_call_allowed_outside_unsafe
    r = check("extern fn foo(x: i32) -> i32;\nfn main() -> i32 { return foo(3); }\n")
    assert_empty r.diagnostics.map(&:to_s)
  end

  def test_extern_missing_body_error
    r = check("fn foo(x: i32) -> i32;\nfn main() -> i32 { return 0; }\n")
    refute_empty r.diagnostics
    assert_match(/must have a body/, r.diagnostics[0].message)
  end

  def test_variadic_extra_args_allowed
    r = check("extern fn printf(fmt: *u8, ...) -> i32;\nfn main() -> i32 { printf(c\"%d\", 1, 2, 3); return 0; }\n")
    assert_empty r.diagnostics.map(&:to_s)
  end

  def test_variadic_too_few_args_error
    r = check("extern fn printf(fmt: *u8, ...) -> i32;\nfn main() -> i32 { printf(); return 0; }\n")
    refute_empty r.diagnostics
    assert_match(/at least 1 argument/, r.diagnostics[0].message)
  end

  def test_fixed_param_type_mismatch
    r = check("extern fn foo(x: i32);\nfn main() -> i32 { foo(c\"hi\"); return 0; }\n")
    refute_empty r.diagnostics
    assert_match(/type mismatch/, r.diagnostics[0].message)
  end

  def test_stdlib_exported_print_callable
    r = check("use \"std/io.cnd\";\nfn main() -> i32 { println(\"hi\"); return 0; }\n")
    assert_empty r.diagnostics.map(&:to_s)
  end

  def test_stdlib_private_write_not_callable
    r = check("use \"std/io.cnd\";\nfn main() -> i32 { write(1, c\"x\", 1); return 0; }\n")
    refute_empty r.diagnostics
    assert_match(/private to its module/, r.diagnostics[0].message)
  end

  # codegen IR

  def test_declare_and_mangled_names
    ir = gen_ok("extern fn foo(x: i32) -> i32;\nfn bar() -> i32 { return foo(1); }\nfn main() -> i32 { return bar(); }\n")
    assert_includes ir, "declare i32 @foo(i32)"
    assert_includes ir, "call i32 (i32) @foo(i32 1)"
    assert_includes ir, "@cinder_bar"
    refute_includes ir, "define i32 @foo"
  end

  def test_declare_variadic_and_void
    ir = gen_ok("extern fn printf(fmt: *u8, ...) -> i32;\nextern fn exit(code: i32);\nfn main() -> i32 { printf(c\"%d\\n\", 7); exit(0); return 0; }\n")
    assert_includes ir, "declare i32 @printf(ptr, ...)"
    assert_includes ir, "declare void @exit(i32)"
    assert_includes ir, "call i32 (ptr, ...) @printf(ptr"
  end

  def test_stdlib_io_declares
    ir = gen_ok("use \"std/io.cnd\";\nfn main() -> i32 { println(\"hi\"); return 0; }\n")
    assert_includes ir, "declare i64 @write(i32, ptr, i64)"
    assert_includes ir, "declare i64 @strlen(ptr)"
    assert_includes ir, "define i32 @cinder_putchar(i32)"
    assert_includes ir, "define void @cinder_println({ ptr, i64 }"
  end

  # run

  def test_run_stdlib_println
    out, code = run_stdout("use \"std/io.cnd\";\nfn main() -> i32 { println(\"Hello from Cinder!\"); return 0; }\n")
    assert_equal "Hello from Cinder!\n", out
    assert_equal 0, code
  end

  def test_run_puts_and_printf
    out, code = run_stdout("use \"std/io.cnd\";\nfn main() -> i32 { puts(c\"plain\"); printf(c\"%d %s\\n\", 40, c\"x\"); return 0; }\n")
    assert_equal "plain\n40 x\n", out
    assert_equal 0, code
  end

  def test_run_number_printing
    out, code = run_stdout(<<~CND)
      use "std/io.cnd";
      fn main() -> i32 {
          let n: i32 = 42;
          print(&n, .I32);
          putchar(10);
          let m: i32 = -7;
          print(&m, .I32);
          putchar(10);
          let u: u64 = 18446744073709551615;
          print(&u, .U64);
          putchar(10);
          return 0;
      }
    CND
    assert_equal "42\n-7\n18446744073709551615\n", out
    assert_equal 0, code
  end

  def test_run_exit_via_libc
    out, code = run_stdout("use \"std/io.cnd\";\nextern fn exit(code: i32);\nfn main() -> i32 { printf(c\"bye\"); exit(3); return 0; }\n")
    assert_equal "bye", out
    assert_equal 3, code
  end

  # ---------- C interop: function pointers and void* ----------

  def test_run_c_callback_into_cinder
    out, code = run_stdout(<<~CND)
      use "std/io.cnd";
      extern fn atexit(cb: fn() -> void) -> i32;
      fn goodbye() {
          println("bye");
      }
      fn main() -> i32 {
          let ok: i32 = atexit(goodbye);
          if ok != 0 { return 1; }
          println("hello");
          return 0;
      }
    CND
    assert_equal "hello\nbye\n", out
    assert_equal 0, code
  end

  def test_run_void_ptr_coerce
    out, code = run_stdout(<<~CND)
      extern fn memset(dst: *void, c: i32, n: usize) -> *void;
      extern fn malloc(n: usize) -> *void;
      fn main() -> i32 {
          let mut x: u64 = 0xdeadbeef;
          memset(&x, 0, 8);
          if x != 0 { return 1; }
          let p: *void = malloc(16);
          if p == null { return 2; }
          unsafe {
              let q: *i32 = p as *i32;
              q[0] = 42;
              if q[0] != 42 { return 3; }
          }
          return 0;
      }
    CND
    assert_equal 0, code
  end

  def test_run_c_qsort_with_cinder_comparator
    out, code = run_stdout(<<~CND)
      extern fn qsort(base: *void, nmemb: usize, size: usize, compar: fn(*void, *void) -> i32);
      unsafe fn cmp(a: *void, b: *void) -> i32 {
          let x: *i32 = a as *i32;
          let y: *i32 = b as *i32;
          return x[0] - y[0];
      }
      fn main() -> i32 {
          let mut arr: [4]i32 = [4, 2, 3, 1];
          unsafe {
              qsort(&arr, 4, 4, cmp);
          }
          if arr[0] != 1 { return 1; }
          if arr[1] != 2 { return 2; }
          if arr[2] != 3 { return 3; }
          if arr[3] != 4 { return 4; }
          return 0;
      }
    CND
    assert_equal 0, code
  end
end
