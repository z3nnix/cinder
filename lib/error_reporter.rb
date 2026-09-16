module Cinder
  class Diagnostic
    attr_reader :file, :line, :col, :message, :level, :notes, :len

    def initialize(file, line, col, message, level: :error, notes: [], len: 1)
      @file = file
      @line = line
      @col = col
      @message = message
      @level = level
      @notes = notes
      @len = len
    end

    def error?
      @level == :error
    end

    def warning?
      @level == :warning
    end

    def to_s
      "#{file}:#{line}:#{col}: #{level}: #{message}"
    end
  end

  class DiagError < StandardError
    attr_reader :diag

    def initialize(file, line, col, message)
      @diag = Diagnostic.new(file, line, col, message)
      super(@diag.to_s)
    end
  end

  class ErrorReporter
    attr_reader :diagnostics

    def initialize
      @diagnostics = []
    end

    def report(file, line, col, message, notes: [], len: 1)
      @diagnostics << Diagnostic.new(file, line, col, message, notes: notes, len: len)
    end

    def warn(file, line, col, message, notes: [], len: 1)
      @diagnostics << Diagnostic.new(file, line, col, message, level: :warning, notes: notes, len: len)
    end

    def error?
      @diagnostics.any?(&:error?)
    end

    def each(&block)
      @diagnostics.each(&block)
    end

    def clear
      @diagnostics.clear
    end
  end
end
