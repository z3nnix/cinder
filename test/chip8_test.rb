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

class Chip8Test < Minitest::Test
  include Cinder
  include Cinder::AST

  ROOT = File.expand_path("..", __dir__)
  TOOLS = %w[llc as cc].select { |t| system("command -v #{t} >/dev/null 2>&1") }

  INCLUDE_DIRS = [File.join(ROOT, "lib"), File.join(ROOT, "examples", "chip8")].freeze

  def setup
    @tmp = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def build(src)
    file = File.join(@tmp, "main.cnd")
    File.write(file, src)
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: INCLUDE_DIRS, reporter: reporter) { |p| File.read(p) }
    program = loader.load(file)
    return [reporter, nil] unless reporter.diagnostics.empty?
    sema = Sema.new(program, reporter)
    sema.check
    return [reporter, nil] unless reporter.diagnostics.empty?
    [reporter, Codegen.new(program, sema).generate]
  end

  def run_exit(src)
    skip "toolchain not available" unless TOOLS.length == 3
    reporter, ir = build(src)
    assert_empty reporter.diagnostics.map(&:to_s), reporter.diagnostics.map(&:to_s)
    refute_nil ir
    ll = File.join(@tmp, "main.ll")
    asm = File.join(@tmp, "main.s")
    obj = File.join(@tmp, "main.o")
    bin = File.join(@tmp, "main")
    File.write(ll, ir)
    assert system("llc", "-O", "0", "-filetype=asm", ll, "-o", asm), "llc failed:\n#{ir}"
    assert system("as", asm, "-o", obj), "as failed:\n#{ir}"
    assert system("cc", "-no-pie", obj, "-o", bin), "cc failed:\n#{ir}"
    out, _err, st = Open3.capture3(bin)
    [st.exitstatus, out]
  end

  def test_emulator_ops
    status, out = run_exit(<<~CND)
      use "std/io.cnd";
      use "chip8.cnd";

      fn fail(what: []u8) -> i32 {
          print("chip8 test FAIL: ");
          println(what);
          return 1;
      }

      fn main() -> i32 {
          let rom: [29]u8 = [
              0x00, 0xE0,                 // 0x200: CLS
              0x60, 0x0A,                 // 0x202: V0=10
              0x61, 0x05,                 // 0x204: V1=5
              0x62, 0xFA,                 // 0x206: V2=250
              0x6D, 0x02, 0xFD, 0x15,     // 0x208: VD=2; DT=2
              0x6E, 0x03, 0xFE, 0x18,     // 0x20C: VE=3; ST=3
              0xA2, 0x1C,                 // 0x210: I=0x21C (sprite)
              0xD0, 0x11,                 // 0x212: draw 1 row at (10,5)
              0xD0, 0x11,                 // 0x214: draw again -> collision
              0x80, 0x24,                 // 0x216: V0 += V2 (carry)
              0x64, 0x7B,                 // 0x218: V4=123
              0xF4, 0x33,                 // 0x21A: BCD V4 -> [I..I+2]
              0x80                        // 0x21C: sprite (bit 7)
          ];
          let c = chip8_new();
          load_rom(&c, rom[..]);

          for i in 0..14 { tick(&c); }
          tick_timers(&c);
          tick_timers(&c);

          if fb_pixel(&c, 10, 5) != 0 { chip8_free(&c); return fail("pixel not cleared by 2nd draw"); }
          if fb_pixel(&c, 10, 6) != 0 { chip8_free(&c); return fail("pixel set below sprite"); }
          if fb_pixel(&c, 9, 5) != 0 { chip8_free(&c); return fail("pixel set left of sprite"); }
          if c.v[15] != 1 { chip8_free(&c); return fail("collision flag not set"); }
          if c.v[0] != 4 { chip8_free(&c); return fail("8xy4 carry add wrong"); }
          if c.v[4] != 123 { chip8_free(&c); return fail("V4 wrong"); }
          let addr: u16 = 0x21C;
          unsafe {
              if c.mem[addr] != 1 { chip8_free(&c); return fail("BCD hundreds"); }
              if c.mem[addr + 1] != 2 { chip8_free(&c); return fail("BCD tens"); }
              if c.mem[addr + 2] != 3 { chip8_free(&c); return fail("BCD ones"); }
          }
          if c.dt != 0 { chip8_free(&c); return fail("delay timer not decremented"); }
          if c.st != 1 { chip8_free(&c); return fail("sound timer wrong"); }
          if c.cycles != 14 { chip8_free(&c); return fail("cycle count wrong"); }

          chip8_free(&c);
          print("chip8 test OK\\n");
          return 0;
      }
    CND
    assert_equal 0, status, "harness failed:\n#{out}"
    assert_includes out, "chip8 test OK"
  end

  def test_emulator_core_compiles_with_stdlib
    reporter, ir = build(<<~CND)
      use "std/io.cnd";
      use "chip8.cnd";
      fn main() -> i32 {
          let c = chip8_new();
          clear_screen(&c);
          chip8_free(&c);
          return 0;
      }
    CND
    assert_empty reporter.diagnostics.map(&:to_s), reporter.diagnostics.map(&:to_s)
    refute_nil ir
  end

  def test_demo_host_compiles
    entry = File.join(ROOT, "examples", "chip8", "main.cnd")
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: INCLUDE_DIRS, reporter: reporter) { |p| File.read(p) }
    program = loader.load(entry)
    sema = Sema.new(program, reporter)
    sema.check
    assert_empty reporter.diagnostics.map(&:to_s), reporter.diagnostics.map(&:to_s)
  end
end
