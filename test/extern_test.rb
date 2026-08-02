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
          print_u32(42);
          print_newline();
          print_i32(-7);
          print_newline();
          print_u64(18446744073709551615);
          print_newline();
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
end
