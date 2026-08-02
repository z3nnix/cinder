require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class BuildTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MAIN = File.join(ROOT, "main.rb")
  TOOLS = %w[llvm-as llc as cc].select { |t| system("command -v #{t} >/dev/null 2>&1") }

  def setup
    @tmp = Dir.mktmpdir
    @file = File.join(@tmp, "main.cnd")
    File.write(@file, <<~CND)
      fn main() -> i32 {
          let mut acc = 0;
          for i in 1..=5 { acc += i; }
          return acc;
      }
    CND
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def run_cli(*args)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, MAIN, *args)
    [stdout, stderr, status]
  end

  def test_emit_llvm_writes_file
    out, err, st = run_cli("build", @file, "--emit=llvm")
    assert_equal 0, st.exitstatus, err
    ll = "#{@file}.ll"
    assert File.exist?(ll), "expected #{ll} to be written\n#{out}\n#{err}"
  end

  def test_emit_llvm_is_valid_ir
    skip "llvm-as not available" unless TOOLS.include?("llvm-as")
    _out, err, st = run_cli("build", @file, "--emit=llvm")
    assert_equal 0, st.exitstatus, err
    ll = "#{@file}.ll"
    _o, e, s = Open3.capture3("llvm-as", ll, "-o", "#{ll}.bc")
    assert_equal 0, s.exitstatus, "llvm-as rejected output:\n#{File.read(ll)}\n#{e}"
  end

  def test_emit_bin_runs
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    bin = File.join(@tmp, "prog")
    _out, err, st = run_cli("build", @file, "--emit=bin", "-o", bin)
    assert_equal 0, st.exitstatus, err
    assert File.exist?(bin)
    _o, _e, s = Open3.capture3(bin)
    assert_equal 15, s.exitstatus, "expected exit code 15 (1+2+3+4+5)"
  end

  def test_no_temp_files_left
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    bin = File.join(@tmp, "prog")
    run_cli("build", @file, "--emit=bin", "-o", bin)
    leftovers = Dir.children(@tmp).reject { |f| f == "main.cnd" || f == "prog" }
    assert_empty leftovers, "temp files left behind: #{leftovers.join(', ')}"
  end

  def test_missing_file_reports_error
    _out, err, st = run_cli("build", File.join(@tmp, "nope.cnd"))
    refute_equal 0, st.exitstatus
    assert_match(/cannot find module|not found|no such file/i, err)
  end

  def test_stdlib_use_default_include_dir
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    file = File.join(@tmp, "hello.cnd")
    File.write(file, "use \"std/io.cnd\";\nfn main() -> i32 { println(\"hi\"); print_u32(5); print_newline(); return 0; }\n")
    bin = File.join(@tmp, "prog")
    out, err, st = run_cli("build", file, "--emit=bin", "-o", bin)
    assert_equal 0, st.exitstatus, err
    _o, _e, s = Open3.capture3(bin)
    assert_equal 0, s.exitstatus
    assert_equal "hi\n5\n", _o
  end

  def test_emit_obj_keeps_object
    _out, err, st = run_cli("build", @file, "--emit=obj")
    assert_equal 0, st.exitstatus, err
    obj = @file.sub(/\.cnd\z/, ".o")
    assert File.exist?(obj), "expected #{obj} to be kept"
    leftovers = Dir.children(@tmp).reject { |f| f == "main.cnd" || f == "main.o" }
    assert_empty leftovers, "temp files left behind: #{leftovers.join(', ')}"
  end

  def test_verbose_keeps_intermediates
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    bin = File.join(@tmp, "prog")
    out, _err, st = run_cli("build", @file, "--emit=bin", "-o", bin, "-v")
    assert_equal 0, st.exitstatus
    assert_match(/keeping intermediates/, out)
    kept = Dir.children(@tmp).select { |f| f.end_with?(".tmp") }
    assert_equal 3, kept.length, "expected .ll/.s/.o temp files to be kept: #{kept.join(', ')}"
  end

  def test_no_verbose_removes_intermediates
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    bin = File.join(@tmp, "prog")
    _out, _err, st = run_cli("build", @file, "--emit=bin", "-o", bin)
    assert_equal 0, st.exitstatus
    leftovers = Dir.children(@tmp).select { |f| f.end_with?(".tmp") }
    assert_empty leftovers, "temp files left behind: #{leftovers.join(', ')}"
  end

  def test_unknown_target_reports_error
    _out, err, st = run_cli("build", @file, "--target=sparc-v8")
    refute_equal 0, st.exitstatus
    assert_match(/unknown target `sparc-v8`/, err)
  end

  def test_known_targets_are_accepted
    _out, err, st = run_cli("build", @file, "--target=x86_64", "--emit=llvm")
    assert_equal 0, st.exitstatus, err
    _out, err, st = run_cli("build", @file, "--target=x86_64-freestanding", "--emit=llvm")
    assert_equal 0, st.exitstatus, err
  end

  def test_release_fast_rejected
    _out, err, st = run_cli("build", @file, "--mode=release-fast")
    refute_equal 0, st.exitstatus
    assert_match(/invalid option|invalid mode|--mode/, err)
  end

  def test_error_output_has_source_snippet
    bad = File.join(@tmp, "bad.cnd")
    File.write(bad, "fn main() {\n    let a: u8 = 300;\n}\n")
    _out, err, st = run_cli("check", bad)
    refute_equal 0, st.exitstatus
    assert_match(/bad\.cnd:2:17: error:/, err)
    assert_match(/\|     let a: u8 = 300;\n\s*\| +\^/, err)
  end

  def test_error_output_no_color_when_not_tty
    bad = File.join(@tmp, "bad.cnd")
    File.write(bad, "fn main() {\n    let a: u8 = 300;\n}\n")
    _out, err, _st = run_cli("check", bad)
    refute_includes err, "\e["
  end

  def test_check_command_reports_ok_program
    _out, err, st = run_cli("check", @file)
    assert_equal 0, st.exitstatus, err
  end
end
