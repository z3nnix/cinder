#!/usr/bin/env ruby
# tools/fuzz.rb -- random Cinder source generator and crash-hunter.
# Usage: ruby tools/fuzz.rb [iterations] [seed]
# Any unhandled exception (other than the compiler's own DiagError) is a bug.

$LOAD_PATH.unshift(File.expand_path("..", __dir__))

require "tmpdir"
require "fileutils"
require_relative "../lib/error_reporter"
require_relative "../lib/lexer"
require_relative "../lib/ast"
require_relative "../lib/parser"
require_relative "../lib/loader"
require_relative "../lib/sema"
require_relative "../lib/targets"
require_relative "../lib/codegen"

module Cinder
  class Fuzzer
    FRAGMENTS = {
      types: %w[i32 u8 u16 u64 i64 f64 bool none void *u8 *i32 *void &&i32 [i32;4] []i32 ?i32 ?bool ?u8],
      exprs: %w[0 1 42 -1 3.14 true false none null x y acc i n ok a b arr[0]
                arr[i] x + y a * b acc + i (a - b) * 2 x / 2 acc % 7
                !ok -n x > 0 x < 100 x >= y x == y x != y
                ok && ok ok || ok x as u8 y as i32 n as f64 3 as u8
                compute(a, b) sum(x, 1) get() arr[i]? maybe()? p.0 f(1, 2, 3)
                [1, 2, 3] Point { x: a, y: b } Color.Red .Red],
      stmts: %w[
        let x: i32 = 1;
        let mut acc = 0;
        let y = 42;
        let n: i32 = -5;
        let ok = true;
        let s = "hello";
        let c = '\x41';
        let p: *i32 = null;
        let q: ?i32 = none;
        acc += 1;
        x = y;
        x += 2;
        y -= 1;
        if x > 0 { return 1; }
        if ok { acc += 1; } else { acc -= 1; }
        if x > 0 { } else if y > 0 { } else { }
        for i in 0..10 { acc += i; }
        for i in 0..=5 { acc += i; }
        for i in 0..10 { if i == 3 { break; } acc += i; }
        while x < 100 { x += 1; }
        loop { break; }
        loop { if ok { break; } continue; }
        { let t = 2; acc += t; }
        unsafe { *p = 1; }
        unsafe { let r = *p; acc += r; }
        defer { acc += 1; }
        return acc;
        return 0;
        return none;
      ],
    }.freeze

    def initialize(iterations, seed)
      @iterations = iterations
      @rng = Random.new(seed)
      @bugs = []
      @runs = 0
      @dir = Dir.mktmpdir("cinder-fuzz")
      at_exit { FileUtils.remove_entry(@dir) }
    end

    def run
      @iterations.times do |i|
        source = case @rng.rand(3)
                 when 0 then junk_string
                 when 1 then random_program
                 else random_program_mutated
                 end
        exercise(source, i)
      end
      if @bugs.empty?
        puts "ok: #{@runs} sources exercised, no unhandled exceptions"
        return 0
      end
      puts "#{@bugs.length} bug(s) found:"
      @bugs.each_with_index do |b, i|
        puts "== bug #{i + 1}: #{b[:error]}"
        puts "file: #{b[:file]}"
        puts b[:source].lines.first(25).map { |l| "  | #{l}" }
      end
      1
    end

    def exercise(source, index)
      file = File.join(@dir, "fuzz_#{index}.cnd")
      File.write(file, source)
      reporter = ErrorReporter.new
      loader = Loader.new(include_dirs: [], reporter: reporter) { |p| File.read(p) }
      program = loader.load(file)
      @runs += 1
      return if reporter.error?
      sema = Sema.new(program, reporter, target: "x86_64")
      sema.check
      return unless reporter.diagnostics.empty?
      Codegen.new(program, sema).generate
    rescue DiagError
    rescue => e
      record_bug(file, source, e)
    end

    def random_program
      parts = []
      rand(1..3).times { parts << random_enum } if @rng.rand(2).zero?
      rand(1..3).times { parts << random_struct }
      rand(1..4).times { parts << random_function(false) }
      parts << random_function(true)
      parts.join("\n\n")
    end

    def random_program_mutated
      src = random_program
      case @rng.rand(3)
      when 0 then src = src[0, @rng.rand(0..src.length)]
      when 1
        pos = @rng.rand(0..src.length)
        src = src[0, pos] + junk_string(@rng.rand(1..8)) + src[pos..]
      when 2
        lines = src.lines
        return random_program if lines.empty?
        lines.delete_at(@rng.rand(lines.length))
        src = lines.join
      end
      src
    end

    def junk_string(n = nil)
      alphabet = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a + "{}()[];:,.+-*/%=!<>?&|^~#'\"_\\".chars
      Array.new(n || @rng.rand(1..12)) { alphabet.sample(random: @rng) }.join
    end

    def random_type
      FRAGMENTS[:types].sample(random: @rng)
    end

    def random_expr
      FRAGMENTS[:exprs].sample(random: @rng)
    end

    def random_stmts(count = @rng.rand(1..6))
      Array.new(count) { FRAGMENTS[:stmts].sample(random: @rng) }.join("\n    ")
    end

    def random_struct
      fields = (1..@rng.rand(1..3)).map { |i| "    f#{i}: #{random_type},\n" }.join
      "struct #{rand_name} {\n#{fields}}"
    end

    def random_enum
      variants = (1..@rng.rand(1..4)).map { rand_name }.join(", ")
      "enum #{rand_name} { #{variants} }"
    end

    def random_function(main)
      name = main ? "main" : rand_name
      ret = main ? " -> i32" : (@rng.rand(3).zero? ? " -> #{random_type}" : "")
      pool = ["x: i32", "y: i32", "a: i32", "b: u8", "n: i32", "ok: bool", "arr: [i32;4]"]
      params = pool.sample(@rng.rand(0..3), random: @rng).join(", ")
      body = random_stmts
      body = "let mut acc = 0;\n    " + body if @rng.rand(2).zero?
      "fn #{name}(#{params})#{ret} {\n    #{body}\n}"
    end

    def rand_name
      "z#{@rng.rand(10_000)}"
    end

    def record_bug(file, source, error)
      @bugs << { file: file, source: source, error: "#{error.class}: #{error.message}" }
    end
  end
end

exit Cinder::Fuzzer.new((ARGV[0] || "500").to_i, (ARGV[1] || "0").to_i).run
