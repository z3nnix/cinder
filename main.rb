#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "error_reporter"
require "lexer"
require "ast"
require "parser"
require "loader"
require "sema"
require "targets"
require "codegen"

module Cinder
  class CLI
    USAGE = <<~TXT
      Usage: main.rb <command> [options] <file.cnd>

      Commands:
        check <file>           run full pipeline: lexer -> parser -> loader -> sema
        build <file>           check + generate LLVM IR (or asm/obj/bin via toolchain)
        tokens <file>          dump tokens (debug)
        ast <file>             dump AST (debug)

      Options:
        -I <dir>               add module search directory (repeatable)
        --target=<arch>        target architecture (default: x86_64)
        --emit=llvm|asm|obj|bin|kernel  output format (default: llvm)
        --mode=debug|release  build mode (default: debug)
        --linker-script=<path> linker script for --emit=kernel
        --boot=<file.s>       assembly boot stub to link into the kernel (e.g. multiboot entry)
        --entry=<name>        kernel entry symbol (default: _start)
        -o <file>              output file (default: <input>.ll/.s/.o/<input>)
        -v, --verbose          keep intermediate files (.ll/.s/.o) and print toolchain commands
        -h, --help             show this help
    TXT

    def self.run(argv, stdout: $stdout, stderr: $stderr)
      new(argv, stdout, stderr).run
    end

    def initialize(argv, stdout, stderr)
      @argv = argv.dup
      @stdout = stdout
      @stderr = stderr
      @include_dirs = [File.expand_path("lib", __dir__)]
    end

    def run
      cmd = @argv.shift
      case cmd
      when nil, "-h", "--help"
        @stdout.puts USAGE
        return 0
      when "check", "build", "tokens", "ast"
        run_command(cmd)
      else
        @stderr.puts "unknown command: #{cmd.inspect}"
        @stderr.puts USAGE
        return 1
      end
    end

    private

    def run_command(cmd)
      file = nil
      dump_tokens = false
      dump_ast = false
      target = "x86_64"
      emit = "llvm"
      mode = :debug
      out = nil
      verbose = false
      linker_script = nil
      boot = nil
      entry = "_start"
      until @argv.empty?
        arg = @argv.shift
        case arg
        when "-I"
          @include_dirs << @argv.shift
        when "--dump-tokens"
          dump_tokens = true
        when "--dump-ast"
          dump_ast = true
        when "-v", "--verbose"
          verbose = true
        when /\A--target=(.+)\z/
          target = Regexp.last_match(1)
        when /\A--emit=(llvm|asm|obj|bin|kernel)\z/
          emit = Regexp.last_match(1)
        when /\A--mode=(debug|release)\z/
          mode = Regexp.last_match(1).to_sym
        when /\A--linker-script=(.+)\z/
          linker_script = Regexp.last_match(1)
        when /\A--boot=(.+)\z/
          boot = Regexp.last_match(1)
        when /\A--entry=(.+)\z/
          entry = Regexp.last_match(1)
        when "-o"
          out = @argv.shift
        else
          file = arg
        end
      end

      if file.nil?
        @stderr.puts "missing file argument"
        @stderr.puts USAGE
        return 1
      end

      unless Targets.known?(target)
        @stderr.puts "error: unknown target `#{target}` (known: #{Targets::TARGETS.keys.join(', ')})"
        return 1
      end

      if emit == "kernel" && linker_script.nil?
        @stderr.puts "error: --emit=kernel requires --linker-script=<path>"
        return 1
      end

      reporter = ErrorReporter.new
      case cmd
      when "tokens"
        dump_tokens(file, reporter)
      when "ast"
        dump_ast(file, reporter)
      when "check"
        check(file, reporter, target: target, dump_tokens: dump_tokens, dump_ast: dump_ast)
      when "build"
        build(file, reporter, target: target, emit: emit, mode: mode, out: out, verbose: verbose,
          linker_script: linker_script, boot: boot, entry: entry)
      end

      unless reporter.diagnostics.empty?
        render_diagnostics(reporter)
        return 1
      end
      0
    rescue Errno::ENOENT
      @stderr.puts "error: file not found: #{file}"
      1
    rescue DiagError => e
      @stderr.puts render_diagnostic(e.diag)
      1
    end

    def render_diagnostics(reporter)
      reporter.each { |d| @stderr.puts render_diagnostic(d) }
    end

    def render_diagnostic(d)
      line_text = source_line(d.file, d.line)
      color = @stderr.respond_to?(:tty?) && @stderr.tty?
      out = +"#{d.file}:#{d.line}:#{d.col}: "
      out << if color
               "\e[1m\e[31merror:\e[0m #{d.message}"
             else
               "error: #{d.message}"
             end
      if line_text
        gutter = d.line.to_s
        pad = " " * gutter.length
        out << "\n"
        out << "  #{gutter} | #{line_text}"
        out << "\n"
        caret = color ? "\e[1m\e[32m^\e[0m" : "^"
        out << "  #{pad} | #{' ' * (d.col - 1)}#{caret}"
      end
      out
    end

    def source_line(file, line)
      src = File.read(file)
      src.lines[line - 1]&.chomp&.gsub("\t", " ")
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def read_source(file)
      File.read(file)
    end

    def parse_module(file, reporter)
      source = read_source(file)
      tokens = Lexer.new(source, file).tokenize
      Parser.new(tokens, file, reporter).parse_program
    end

    def dump_tokens(file, reporter)
      source = read_source(file)
      Lexer.new(source, file).tokenize.each do |tok|
        @stdout.puts tok.to_s
      end
    end

    def dump_ast(file, reporter)
      loader = Loader.new(include_dirs: @include_dirs, reporter: reporter) do |path|
        read_source(path)
      end
      program = loader.load(file)
      raise DiagError.new(file, 1, 1, "parse aborted") if reporter.error?
      @stdout.puts AST::Dumper.dump(program)
    end

    def check(file, reporter, target: "x86_64", dump_tokens: false, dump_ast: false)
      loader = Loader.new(include_dirs: @include_dirs, reporter: reporter) do |path|
        read_source(path)
      end
      program = loader.load(file)
      return if reporter.error?

      sema = Sema.new(program, reporter, target: target)
      sema.check

      if dump_ast
        @stdout.puts AST::Dumper.dump(program)
      end
      if dump_tokens
        source = read_source(file)
        Lexer.new(source, file).tokenize.each do |tok|
          @stdout.puts tok.to_s
        end
      end
    end

    def build(file, reporter, target:, emit:, mode:, out:, verbose:, linker_script: nil, boot: nil, entry: "_start")
      loader = Loader.new(include_dirs: @include_dirs, reporter: reporter) do |path|
        read_source(path)
      end
      program = loader.load(file)
      return if reporter.error?

      sema = Sema.new(program, reporter, target: target)
      sema.check
      return if reporter.error?

      codegen = Codegen.new(program, sema, target: target, mode: mode)
      ir = codegen.generate

      if emit == "llvm"
        path = out || "#{file}.ll"
        File.write(path, ir)
        @stdout.puts "wrote #{path}"
        return
      end

      missing = %w[llc as cc].reject { |t| tool_available?(t) }
      missing = %w[llc as ld objcopy].reject { |t| tool_available?(t) } if emit == "kernel"
      unless missing.empty?
        @stderr.puts "error: missing required tools: #{missing.join(', ')} (install LLVM + binutils + a C compiler)"
        return
      end

      ll_file = write_tmp_ll(file, ir)
      tmp_files = [ll_file]
      ok = false
      path = nil
      begin
        case emit
        when "asm"
          path = out || file.sub(/\.cnd\z/, ".s")
          ok = sh("llc", opt_flag(mode), "-filetype=asm", ll_file, "-o", path, verbose: verbose)
          @stdout.puts "wrote #{path}" if ok
        when "obj"
          path = out || file.sub(/\.cnd\z/, ".o")
          ok = run_toolchain(ll_file, obj: path, mode: mode, tmp_files: tmp_files, verbose: verbose)
          @stdout.puts "wrote #{path}" if ok
        when "bin"
          path = out || file.sub(/\.cnd\z/, "")
          ok = run_toolchain(ll_file, bin: path, mode: mode, tmp_files: tmp_files, verbose: verbose)
          @stdout.puts "wrote #{path}" if ok
        when "kernel"
          path = out || file.sub(/\.cnd\z/, "")
          ok = run_toolchain(ll_file, kernel: path, target: target, linker_script: linker_script,
            boot: boot, entry: entry, mode: mode, tmp_files: tmp_files, verbose: verbose)
          @stdout.puts "wrote #{path}" if ok
        end
      ensure
        if verbose
          @stdout.puts "keeping intermediates:"
          tmp_files.each { |f| @stdout.puts "  #{f}" }
        else
          tmp_files.each { |f| File.delete(f) if File.exist?(f) && f != path }
        end
      end
      ok
    end

    def tool_available?(tool)
      system("command -v #{tool} >/dev/null 2>&1")
    end

    def opt_flag(mode)
      "-O#{mode == :debug ? "0" : "2"}"
    end

    def sh(*cmd, verbose:)
      @stdout.puts cmd.join(" ") if verbose
      system(*cmd)
    end

    def write_tmp_ll(file, ir)
      path = "#{file}.ll.tmp"
      File.write(path, ir)
      path
    end

    def run_toolchain(ll_file, obj: nil, bin: nil, kernel: nil, target: "x86_64", linker_script: nil,
      boot: nil, entry: "_start", mode: :debug, tmp_files: [], verbose: false)
      asm = ll_file.sub(/\.ll\.tmp\z/, ".s.tmp")
      obj_file = obj || "#{asm.sub(/\.s\.tmp\z/, "")}.o.tmp"
      tmp_files << asm << obj_file
      return false unless sh("llc", opt_flag(mode), "-filetype=asm", ll_file, "-o", asm, verbose: verbose)
      return false unless sh("as", asm, "-o", obj_file, verbose: verbose)
      return true unless bin || kernel
      if kernel
        objs = [obj_file]
        unless boot.nil?
          boot_obj = "#{obj_file}.boot.o.tmp"
          tmp_files << boot_obj
          return false unless sh("as", boot, "-o", boot_obj, verbose: verbose)
          objs.unshift(boot_obj)
        end
        emul = Targets[target][:ld_emulation]
        linked = "#{kernel}.elf64.tmp"
        tmp_files << linked
        return false unless sh("ld", "-m", emul, "-T", linker_script, "--entry=#{entry}", "-o", linked, *objs, verbose: verbose)
        sh("objcopy", "-O", "elf32-i386", linked, kernel, verbose: verbose)
      else
        sh("cc", "-no-pie", obj_file, "-lm", "-o", bin, verbose: verbose)
      end
    end
  end
end

exit Cinder::CLI.run(ARGV)
