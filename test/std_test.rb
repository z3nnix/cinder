require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class StdTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MAIN = File.join(ROOT, "main.rb")
  TOOLS = %w[llvm-as llc as cc].select { |t| system("command -v #{t} >/dev/null 2>&1") }

  def build_run(src)
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    Dir.mktmpdir do |dir|
      file = File.join(dir, "main.cnd")
      File.write(file, src)
      bin = File.join(dir, "prog")
      _out, err, st = Open3.capture3(RbConfig.ruby, MAIN, "build", file, "--emit=bin", "-o", bin)
      assert_equal 0, st.exitstatus, "build failed:\n#{err}"
      out, _err, run_st = Open3.capture3(bin)
      [out, run_st.exitstatus]
    end
  end

  def assert_driver(src, marker)
    out, code = build_run(src)
    assert_equal 0, code, "#{marker} driver failed with exit #{code}:\n#{out}"
    assert_includes out, marker
  end

  def build_run_stdin(src, input)
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    Dir.mktmpdir do |dir|
      file = File.join(dir, "main.cnd")
      File.write(file, src)
      bin = File.join(dir, "prog")
      _out, err, st = Open3.capture3(RbConfig.ruby, MAIN, "build", file, "--emit=bin", "-o", bin)
      assert_equal 0, st.exitstatus, "build failed:\n#{err}"
      out, err_out, run_st = Open3.capture3(bin, stdin_data: input)
      [out, err_out, run_st.exitstatus]
    end
  end

  def test_ascii
    assert_driver(<<~CND, "ascii ok")
      use "std/core/ascii.cnd";
      use "std/io.cnd";

      fn main() -> i32 {
          if !ascii_is_digit('5' as u8) { return 1; }
          if ascii_is_digit('x' as u8) { return 2; }
          if !ascii_is_hex_digit('F' as u8) { return 3; }
          if ascii_is_hex_digit('g' as u8) { return 4; }
          if !ascii_is_alpha('z' as u8) { return 5; }
          if ascii_is_alpha('9' as u8) { return 6; }
          if !ascii_is_alnum('7' as u8) { return 7; }
          if !ascii_is_space('\\t' as u8) { return 8; }
          if ascii_is_space('x' as u8) { return 9; }
          if !ascii_is_print('~' as u8) { return 10; }
          if ascii_is_print('\\n' as u8) { return 11; }
          if ascii_to_lower('A' as u8) != 'a' as u8 { return 12; }
          if ascii_to_lower('7' as u8) != '7' as u8 { return 13; }
          if ascii_to_upper('z' as u8) != 'Z' as u8 { return 14; }
          let d = ascii_digit_value('9' as u8) else { return 15; };
          if d != 9 { return 16; }
          let e = ascii_digit_value('0' as u8) else { return 17; };
          if e != 0 { return 18; }
          let h = ascii_digit_value('f' as u8) else { return 19; };
          if h != 15 { return 20; }
          let b = ascii_digit_value('B' as u8) else { return 21; };
          if b != 11 { return 22; }
          if ascii_digit_value('@' as u8) != none { return 23; }
          println("ascii ok");
          return 0;
      }
    CND
  end

  def test_mem
    assert_driver(<<~CND, "mem ok")
      use "std/core/mem.cnd";
      use "std/io.cnd";

      fn main() -> i32 {
          let mut a: [8]u8 = [1, 2, 3, 4, 5, 6, 7, 8];
          let mut b: [8]u8 = [0, 0, 0, 0, 0, 0, 0, 0];
          let ap = a[..].ptr;
          let bp = b[..].ptr;

          mem_fill(bp, 7, 8);
          if b[0] != 7 { return 1; }
          if b[7] != 7 { return 2; }

          mem_zero(bp, 8);
          if b[3] != 0 { return 3; }

          mem_fill(ap, 9, 8);
          mem_copy(bp, ap, 8);
          if b[0] != 9 { return 4; }
          if b[7] != 9 { return 5; }

          // backward move: dst = bp, src = bp + 4
          mem_fill(bp, 1, 4);
          unsafe {
              mem_fill(bp + 4, 2, 4);
              mem_move(bp, bp + 4, 4);
          }
          if b[0] != 2 { return 6; }
          if b[3] != 2 { return 7; }

          // forward move: dst = bp + 4, src = bp
          mem_fill(bp, 3, 4);
          unsafe {
              mem_move(bp + 4, bp, 4);
          }
          if b[4] != 3 { return 8; }
          if b[7] != 3 { return 9; }

          if mem_align_up(9, 8) != 16 { return 10; }
          if mem_align_up(16, 8) != 16 { return 11; }
          if mem_align_down(17, 8) != 16 { return 12; }
          if mem_align_down(8, 8) != 8 { return 13; }

          println("mem ok");
          return 0;
      }
    CND
  end

  def test_str
    assert_driver(<<~CND, "str ok")
      use "std/core/str.cnd";
      use "std/io.cnd";

      fn has_sep(s: []u8, sep: []u8) -> bool {
          let _sp = str_split_once(s, sep) else { return false; };
          return true;
      }

      fn main() -> i32 {
          let s: []u8 = "hello world";

          let r = str_index_of(s, "world") else { return 1; };
          if r != 6 { return 2; }
          let r2 = str_index_of(s, "o") else { return 3; };
          if r2 != 4 { return 4; }
          let r3 = str_index_of(s, "") else { return 5; };
          if r3 != 0 { return 6; }
          if str_index_of(s, "hello world!") != none { return 7; }
          if str_index_of(s, "xyz") != none { return 8; }

          if !str_contains(s, "world") { return 9; }
          if str_contains(s, "xyz") { return 10; }

          if !str_starts_with(s, "hello") { return 11; }
          if str_starts_with(s, "world") { return 12; }
          if !str_starts_with(s, "") { return 13; }

          if !str_ends_with(s, "world") { return 14; }
          if str_ends_with(s, "hello") { return 15; }

          let t: []u8 = "  hi  ";
          if str_len(str_trim(t)) != 2 { return 16; }
          if str_len(str_trim_start(t)) != 4 { return 17; }
          if str_len(str_trim_end(t)) != 4 { return 18; }
          if !str_equal(str_trim(t), "hi") { return 19; }

          if !str_equal(str_sub(s, 0, 5), "hello") { return 20; }
          if !str_equal(str_sub(s, 6, 11), "world") { return 21; }
          if str_len(str_sub(s, 5, 3)) != 0 { return 22; }
          if str_len(str_sub(s, 0, 99)) != 0 { return 23; }

          if !has_sep(s, " ") { return 24; }
          let sp = str_split_once(s, " ") else { return 24; };
          if !str_equal(sp.left, "hello") { return 25; }
          if !str_equal(sp.right, "world") { return 26; }
          if has_sep(s, "!") { return 27; }

          if str_compare("a", "b") >= 0 { return 28; }
          if str_compare("abc", "ab") <= 0 { return 29; }
          if str_compare("ab", "ab") != 0 { return 30; }
          if !str_equal("x", "x") { return 31; }

          if str_count("aaa", "a") != 3 { return 32; }
          if str_count("abab", "ab") != 2 { return 33; }
          if str_count("abab", "") != 0 { return 34; }
          if str_count("abab", "x") != 0 { return 35; }

          let p1 = str_parse_u64("12345") else { return 36; };
          if p1 != 12345 { return 37; }
          let p2 = str_parse_u64("0") else { return 38; };
          if p2 != 0 { return 39; }
          if str_parse_u64("12x") != none { return 40; }
          if str_parse_u64("99999999999999999999") != none { return 41; }
          if str_parse_u64("") != none { return 42; }

          let h = str_parse_u64_radix("ff", 16) else { return 43; };
          if h != 255 { return 44; }
          let bin = str_parse_u64_radix("101", 2) else { return 45; };
          if bin != 5 { return 46; }
          if str_parse_u64_radix("12", 2) != none { return 47; }
          if str_parse_u64_radix("ff", 37) != none { return 48; }

          let n1 = str_parse_i64("-42") else { return 49; };
          if n1 != -42 { return 50; }
          let n2 = str_parse_i64("9223372036854775807") else { return 51; };
          if n2 != 9223372036854775807 { return 52; }
          let n3 = str_parse_i64("-9223372036854775808") else { return 53; };
          if n3 != -9223372036854775808 { return 54; }
          if str_parse_i64("9223372036854775808") != none { return 55; }
          if str_parse_i64("-9223372036854775809") != none { return 56; }
          if str_parse_i64("+5") != none { return 57; }
          if str_parse_i64("") != none { return 58; }
          if str_parse_i64("-") != none { return 59; }

          let f1 = str_parse_f64("3.25") else { return 60; };
          if f1 != 3.25 { return 61; }
          let f2 = str_parse_f64("-0.5") else { return 62; };
          if f2 != -0.5 { return 63; }
          let f3 = str_parse_f64("2e3") else { return 64; };
          if f3 != 2000.0 { return 65; }
          let f4 = str_parse_f64("12") else { return 66; };
          if f4 != 12.0 { return 67; }
          if str_parse_f64("abc") != none { return 68; }
          if str_parse_f64("12e") != none { return 69; }
          if str_parse_f64("") != none { return 70; }
          if str_parse_f64("-") != none { return 71; }

          println("str ok");
          return 0;
      }
    CND
  end

  def test_format
    assert_driver(<<~CND, "format ok")
      use "std/core/format.cnd";
      use "std/core/str.cnd";
      use "std/io.cnd";

      fn main() -> i32 {
          let mut buf: [40]u8 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
          let bp = buf[..].ptr;

          let n1 = fmt_u64(12345, bp, 40);
          if n1 != 5 { return 1; }
          if !str_equal(buf[0 .. n1], "12345") { return 2; }

          let n2 = fmt_u64(0, bp, 40);
          if n2 != 1 { return 3; }
          if !str_equal(buf[0 .. n2], "0") { return 4; }

          let n3 = fmt_i64(-987, bp, 40);
          if n3 != 4 { return 5; }
          if !str_equal(buf[0 .. n3], "-987") { return 6; }

          let n4 = fmt_i64(-9223372036854775808, bp, 40);
          if n4 != 20 { return 7; }
          if !str_equal(buf[0 .. n4], "-9223372036854775808") { return 8; }

          let n5 = fmt_u128(340282366920938463463374607431768211455, bp, 40);
          if n5 != 39 { return 9; }
          if !str_equal(buf[0 .. n5], "340282366920938463463374607431768211455") { return 10; }

          let n6 = fmt_hex_u64(255, bp, 40);
          if n6 != 2 { return 11; }
          if !str_equal(buf[0 .. n6], "ff") { return 12; }

          let n7 = fmt_hex_u64(0, bp, 40);
          if n7 != 1 { return 13; }
          if !str_equal(buf[0 .. n7], "0") { return 14; }

          let n8 = fmt_hex_u64(0xdeadbeef, bp, 40);
          if n8 != 8 { return 15; }
          if !str_equal(buf[0 .. n8], "deadbeef") { return 16; }

          let n9 = fmt_bool(true, bp, 40);
          if n9 != 4 { return 17; }
          if !str_equal(buf[0 .. n9], "true") { return 18; }

          let n10 = fmt_bool(false, bp, 40);
          if n10 != 5 { return 19; }
          if !str_equal(buf[0 .. n10], "false") { return 20; }

          let p = &buf[0];
          let n11 = fmt_ptr(p, bp, 40);
          if n11 < 3 { return 21; }
          if buf[0] != '0' as u8 { return 22; }
          if buf[1] != 'x' as u8 { return 23; }

          println("format ok");
          return 0;
      }
    CND
  end

  def test_vec
    assert_driver(<<~CND, "vec ok")
      use "std/vec.cnd";
      use "std/io.cnd";

      fn main() -> i32 {
          let mut v: Vec = Vec { data: null, len: 0, cap: 0 };
          vec_init(&v);
          if vec_len(&v) != 0 { return 1; }
          if !vec_push(&v, 65) { return 2; }
          if !vec_push(&v, 66) { return 3; }
          if !vec_push(&v, 67) { return 4; }
          if vec_len(&v) != 3 { return 5; }

          let b0 = vec_get(&v, 0) else { return 6; };
          if b0 != 65 { return 7; }
          if vec_get(&v, 3) != none { return 8; }
          if !vec_set(&v, 1, 98) { return 9; }
          let b1 = vec_get(&v, 1) else { return 10; };
          if b1 != 98 { return 11; }
          if vec_set(&v, 9, 1) { return 12; }

          let p = vec_pop(&v) else { return 13; };
          if p != 67 { return 14; }
          if vec_len(&v) != 2 { return 15; }

          let mut w: Vec = vec_from_slice("hello");
          if vec_as_slice(&w).len != 5 { return 16; }
          if vec_as_slice(&w)[0] != 'h' as u8 { return 17; }
          if vec_as_slice(&w)[4] != 'o' as u8 { return 18; }

          let mut x: Vec = Vec { data: null, len: 0, cap: 0 };
          if !vec_reserve(&x, 16) { return 19; }
          vec_clear(&x);
          if vec_len(&x) != 0 { return 20; }

          vec_deinit(&v);
          vec_deinit(&w);
          vec_deinit(&x);
          println("vec ok");
          return 0;
      }
    CND
  end

  def test_string
    assert_driver(<<~CND, "string ok")
      use "std/string.cnd";
      use "std/core/str.cnd";
      use "std/io.cnd";

      fn main() -> i32 {
          let mut s: String = string_new();
          if !string_empty(&s) { return 1; }
          if !string_append(&s, "hi") { return 2; }
          if !string_push_byte(&s, '!' as u8) { return 3; }
          if string_len(&s) != 3 { return 4; }
          if !str_equal(string_as_slice(&s), "hi!") { return 5; }
          if !string_contains(&s, "i!") { return 6; }
          if string_contains(&s, "zz") { return 7; }

          let mut t: String = string_from("world");
          if string_equal(&s, &t) { return 8; }
          if !string_append_str(&s, &t) { return 9; }
          if !str_equal(string_as_slice(&s), "hi!world") { return 10; }
          let at = string_find(&s, "wor") else { return 11; };
          if at != 3 { return 12; }

          string_clear(&s);
          if !string_empty(&s) { return 13; }
          if !string_append(&s, "again") { return 14; }
          if !str_equal(string_as_slice(&s), "again") { return 15; }

          string_deinit(&s);
          string_deinit(&t);
          println("string ok");
          return 0;
      }
    CND
  end

  def test_math
    assert_driver(<<~CND, "math ok")
      use "std/core/math.cnd";
      use "std/io.cnd";

      fn main() -> i32 {
          if math_abs(-7) != 7 { return 1; }
          if math_abs(7) != 7 { return 2; }
          if math_abs_diff(-3, 5) != 8 { return 3; }
          if math_abs_diff(5, 2) != 3 { return 4; }
          if math_min(3, 5) != 3 { return 5; }
          if math_max(3, 5) != 5 { return 6; }
          if math_clamp(1, 2, 4) != 2 { return 7; }
          if math_clamp(9, 2, 4) != 4 { return 8; }
          if math_clamp(3, 2, 4) != 3 { return 9; }
          if math_min_u(3, 5) != 3 { return 10; }
          if math_max_u(3, 5) != 5 { return 11; }
          if math_clamp_u(1, 2, 4) != 2 { return 12; }
          if !math_is_pow2(1024) { return 13; }
          if math_is_pow2(0) { return 14; }
          if math_is_pow2(3) { return 15; }
          if math_log2(1024) != 10 { return 16; }
          if math_log2(1) != 0 { return 17; }
          if math_pow(2, 10) != 1024 { return 18; }
          if math_pow(3, 3) != 27 { return 19; }
          if math_pow(5, 0) != 1 { return 20; }
          if math_gcd(12, 18) != 6 { return 21; }
          if math_gcd(7, 13) != 1 { return 22; }
          if math_fabs(-2.5) != 2.5 { return 23; }
          if math_floor(3.7) != 3.0 { return 24; }
          if math_floor(-3.2) != -4.0 { return 25; }
          if math_ceil(3.2) != 4.0 { return 26; }
          if math_ceil(-3.7) != -3.0 { return 27; }
          if math_fmin(1.5, 2.5) != 1.5 { return 28; }
          if math_fmax(1.5, 2.5) != 2.5 { return 29; }
          println("math ok");
          return 0;
      }
    CND
  end

  def test_io
    out, err_out, code = build_run_stdin(<<~CND, "hello world\n")
      use "std/io.cnd";
      use "std/core/str.cnd";

      fn main() -> i32 {
          println("io a");
          print_u128(340282366920938463463374607431768211455);
          putchar(10);
          print_i128(-42);
          putchar(10);
          print_hex_u64(0xdeadbeef);
          putchar(10);
          print_hex_u32(0xff);
          putchar(10);
          print_hex_u8(15);
          putchar(10);
          println_err("err io");
          let mut buf: [64]u8 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
          let n = read_line(buf[..].ptr, 64);
          if n == 0 { return 1; }
          if !str_equal(buf[0 .. n], "hello world") { return 2; }
          println("io ok");
          return 0;
      }
    CND
    assert_equal 0, code, "io driver failed with exit #{code}:\n#{out}"
    assert_includes out, "io a"
    assert_includes out, "340282366920938463463374607431768211455"
    assert_includes out, "-42"
    assert_includes out, "deadbeef"
    assert_includes out, "ff"
    assert_includes out, "f"
    assert_includes out, "io ok"
    assert_includes err_out, "err io"
  end

  def test_panic
    out, err_out, code = build_run_stdin(<<~CND, "")
      use "std/panic.cnd";

      fn main() -> i32 {
          panic("boom");
          return 0;
      }
    CND
    assert_equal 1, code, "panic driver exited with #{code}:\n#{out}\n#{err_out}"
    assert_includes err_out, "boom"
  end
end
