module Cinder
  class Diagnostic
    attr_reader :file, :line, :col, :message

    def initialize(file, line, col, message)
      @file = file
      @line = line
      @col = col
      @message = message
    end

    def to_s
      "#{file}:#{line}:#{col}: error: #{message}"
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

    def report(file, line, col, message)
      @diagnostics << Diagnostic.new(file, line, col, message)
    end

    def error?(diag = nil)
      @diagnostics.any?
    end

    def each(&block)
      @diagnostics.each(&block)
    end

    def clear
      @diagnostics.clear
    end
  end
end
