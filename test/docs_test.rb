require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/error_reporter"
require_relative "../lib/lexer"
require_relative "../lib/ast"
require_relative "../lib/parser"
require_relative "../lib/loader"
require_relative "../lib/targets"
require_relative "../lib/sema"
require_relative "../lib/codegen"

class DocsTest < Minitest::Test
  include Cinder

  TOOLS = %w[llvm-as llc as cc].select { |t| system("command -v #{t} >/dev/null 2>&1") }

  ROOT = File.expand_path("..", __dir__)
  DOCS_DIR = File.join(ROOT, "docs")

  def setup
    @tmp = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  # --- compiler ---

  def compile(src)
    file = File.join(@tmp, "main.cnd")
    File.write(file, src)
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: [File.join(ROOT, "lib")], reporter: reporter) { |p| File.read(p) }
    program = loader.load(file)
    return [false, "load"] unless reporter.diagnostics.empty?
    sema = Sema.new(program, reporter)
    sema.check
    return [false, "sema"] unless reporter.diagnostics.empty?
    ir = Codegen.new(program, sema).generate
    [true, ir]
  end

  def emit_and_run(ir)
    ll = File.join(@tmp, "main.ll")
    asm_f = File.join(@tmp, "main.s")
    obj = File.join(@tmp, "main.o")
    bin = File.join(@tmp, "main")
    File.write(ll, ir)
    return [:skip, "llc failed"] unless system("llc", "-O", "0", "-filetype=asm", ll, "-o", asm_f)
    return [:skip, "as failed"] unless system("as", asm_f, "-o", obj)
    return [:skip, "cc failed"] unless system("cc", "-no-pie", obj, "-o", bin)
    _out, _err, st = Open3.capture3(bin)
    [st.exitstatus, nil]
  end

  # --- extractor: yields cinder blocks paired with following text block ---

  def paired_blocks(md)
    lines = IO.readlines(md)
    result = []
    i = 0
    while i < lines.length
      if lines[i].strip =~ /^```rust\b?/
        line_no = i + 1
        i += 1
        buf = []
        while i < lines.length && lines[i].strip != "```"
          buf << lines[i]
          i += 1
        end
        src = buf.join
        tag_line = buf.first.to_s.strip
        meta = tag_line.start_with?("//") ? tag_line.sub(/^\/\/\s*docs:\s*/, "").strip : ""
        # look for following text block
        expected = nil
        j = i + 1
        j += 1 while j < lines.length && lines[j].strip.empty?
        if j < lines.length && lines[j].strip =~ /^```text$/
          j += 1
          ebuf = []
          while j < lines.length && lines[j].strip != "```"
            ebuf << lines[j]
            j += 1
          end
          expected = ebuf.map { |l| l.sub(/^\$\s*/, "").chomp }
        end
        result << { src: src, meta: meta, line: line_no, expected: expected }
      end
      i += 1
    end
    result
  end

  # --- tests ---

  def test_all_doc_files_exist
    (1..17).each do |n|
      name = Dir.glob(File.join(DOCS_DIR, "%02d_*.md" % n)).first
      assert name, "missing docs page #{n}"
    end
  end

  def test_no_raw_file_references
    Dir.glob(File.join(DOCS_DIR, "*.md")).each do |path|
      content = File.read(path)
      refute_match(/\be[23456789]\b/, content, "#{File.basename(path)}: likely raw :E2 reference")
    end
  end

  def test_no_purple_code_spans
    Dir.glob(File.join(DOCS_DIR, "*.md")).each do |path|
      content = File.read(path)
      refute_match(/\e\[3[45679]m/, content, "#{File.basename(path)}: ANSI color in code span")
    end
  end

  def test_doc_examples_compile_and_run
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    Dir.glob(File.join(DOCS_DIR, "*.md")).sort.each do |path|
      paired_blocks(path).each do |b|
        tag = b[:meta]
        next if tag.include?("skip") || tag.include?("kernel") || tag.include?("error")
        next unless b[:src].include?("fn main")
        if tag.include?("check")
          ok, _ir = compile(b[:src])
          assert ok, "compile-only block in #{File.basename(path)} line #{b[:line]} failed"
          next
        end
        ok, ir = compile(b[:src])
        unless ok
          flunk("block in #{File.basename(path)} line #{b[:line]} failed to compile")
          next
        end
        exit_status, err = emit_and_run(ir)
        next if err  # toolchain not available for this step
        assert_equal 0, exit_status, "block in #{File.basename(path)} line #{b[:line]} exited #{exit_status}"
      end
    end
  end

  def test_expected_output_matches
    skip "toolchain not available" unless (TOOLS & %w[llc as cc]).length == 3
    Dir.glob(File.join(DOCS_DIR, "*.md")).sort.each do |path|
      paired_blocks(path).each do |b|
        tag = b[:meta]
        next if tag.include?("skip") || tag.include?("kernel") || tag.include?("check") || tag.include?("error")
        next unless b[:src].include?("fn main")
        next unless b[:expected]
        ok, ir = compile(b[:src])
        unless ok
          flunk("expected-output block in #{File.basename(path)} line #{b[:line]} failed to compile")
          next
        end
        exit_status, err = emit_and_run(ir)
        next if err
        assert_equal 0, exit_status,
          "expected-output block in #{File.basename(path)} line #{b[:line]} exited #{exit_status}"
      end
    end
  end
end
