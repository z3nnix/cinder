module Cinder
  class Loader
    include AST

    def initialize(include_dirs:, reporter:, &source_reader)
      @include_dirs = include_dirs
      @reporter = reporter
      @source_reader = source_reader
      @loaded = {}
      @loading = []
      @all_decls = []
    end

    def load(entry_path)
      @all_decls = []
      entry = parse_program(entry_path)
      return Program.new(1, 1, decls: @all_decls, uses: [], path: entry_path) if entry.nil?
      Program.new(1, 1, decls: @all_decls, uses: entry.uses, path: entry_path)
    end

    private

    def expand_path(path)
      File.expand_path(path)
    end

    def parse_program(path)
      expanded = expand_path(path)

      if @loading.include?(expanded)
        @reporter.report(path, 1, 1, "circular import detected: #{expanded}")
        return nil
      end
      return @loaded[expanded] if @loaded.key?(expanded)

      source = @source_reader.call(expanded)
      return nil if source.nil?

      tokens = Lexer.new(source, expanded).tokenize
      parser = Parser.new(tokens, expanded, @reporter)
      program = parser.parse_program
      program.path = expanded

      @loaded[expanded] = program
      program.decls.each do |decl|
        decl.module_file = expanded
        @all_decls << decl
      end

      @loading << expanded
      program.uses.each do |use|
        resolved = resolve(use.path, File.dirname(expanded))
        if resolved.nil?
          @reporter.report(expanded, use.line, use.col, "cannot find module `#{use.path}`")
          next
        end
        sub = parse_program(resolved)
        use.module_ref = sub if sub
      end
      @loading.pop

      program
    rescue Errno::ENOENT
      @reporter.report(path, 1, 1, "cannot find module `#{path}`")
      nil
    rescue DiagError => e
      @reporter.report(e.diag.file, e.diag.line, e.diag.col, e.diag.message)
      nil
    end

    def resolve(path, from_dir)
      candidates = []
      if path.start_with?("/")
        candidates << path
      else
        candidates << File.join(from_dir, path)
        @include_dirs.each { |dir| candidates << File.join(dir, path) }
      end
      candidates.find { |c| File.file?(c) }
    end
  end
end
