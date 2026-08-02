require "minitest/autorun"
require "tmpdir"
require_relative "../lib/error_reporter"
require_relative "../lib/lexer"
require_relative "../lib/ast"
require_relative "../lib/parser"
require_relative "../lib/loader"

class LoaderTest < Minitest::Test
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

  def load(entry, include_dirs: [])
    reporter = ErrorReporter.new
    loader = Loader.new(include_dirs: include_dirs, reporter: reporter) { |p| File.read(p) }
    program = loader.load(File.join(@tmp, entry))
    [program, reporter]
  end

  def test_single_module
    write("main.cnd", "fn main() { }\n")
    program, reporter = load("main.cnd")
    assert_equal 1, program.decls.length
    assert_empty reporter.diagnostics
  end

  def test_import_merges_decls
    write("uart.cnd", "export fn uart_init() { }\n")
    write("main.cnd", "use \"uart.cnd\";\nfn main() { }\n")
    program, reporter = load("main.cnd")
    assert_empty reporter.diagnostics
    assert_equal 2, program.decls.length
    names = program.decls.map(&:name)
    assert_includes names, "uart_init"
    assert_includes names, "main"
    assert program.decls.find { |d| d.name == "uart_init" }.exported
  end

  def test_dedup
    write("common.cnd", "export fn helper() { }\n")
    write("a.cnd", "use \"common.cnd\";\n")
    write("b.cnd", "use \"common.cnd\";\n")
    write("main.cnd", "use \"a.cnd\";\nuse \"b.cnd\";\nfn main() { }\n")
    program, reporter = load("main.cnd")
    assert_empty reporter.diagnostics
    helpers = program.decls.select { |d| d.name == "helper" }
    assert_equal 1, helpers.length, "module loaded twice"
  end

  def test_circular_import
    write("a.cnd", "use \"b.cnd\";\nexport fn fa() { }\n")
    write("b.cnd", "use \"a.cnd\";\nexport fn fb() { }\n")
    program, reporter = load("a.cnd")
    assert_operator reporter.diagnostics.length, :>=, 1
    assert_match(/circular import/, reporter.diagnostics[0].message)
  end

  def test_missing_module
    write("main.cnd", "use \"nope.cnd\";\nfn main() { }\n")
    program, reporter = load("main.cnd")
    assert_operator reporter.diagnostics.length, :>=, 1
    assert_match(/cannot find module/, reporter.diagnostics[0].message)
  end

  def test_include_dirs
    write("lib/uart.cnd", "export fn uart_init() { }\n")
    write("main.cnd", "use \"uart.cnd\";\nfn main() { }\n")
    program, reporter = load("main.cnd", include_dirs: [File.join(@tmp, "lib")])
    assert_empty reporter.diagnostics
    assert_equal 2, program.decls.length
  end

  def test_private_not_exported_still_loaded
    write("uart.cnd", "fn internal_helper() { }\nexport fn uart_init() { }\n")
    write("main.cnd", "use \"uart.cnd\";\nfn main() { }\n")
    program, reporter = load("main.cnd")
    assert_empty reporter.diagnostics
    assert_equal 3, program.decls.length
  end

  def test_syntax_error_reported
    write("bad.cnd", "fn main( {\n")
    program, reporter = load("bad.cnd")
    assert_operator reporter.diagnostics.length, :>=, 1
  end
end
