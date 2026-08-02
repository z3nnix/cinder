module Cinder
  class Token
    attr_reader :type, :line, :col
    attr_accessor :value

    def initialize(type, value, line, col)
      @type = type
      @value = value
      @line = line
      @col = col
    end

    def to_s
      "#{type}(#{value.inspect})@#{line}:#{col}"
    end
  end

  class Lexer
    KEYWORDS = %w[
      as break const continue defer else enum extern fn for if let loop mut
      return switch unsafe use while volatile
    ].to_h { |k| [k, k.to_sym] }

    INT_TYPES = %w[u8 u16 u32 u64 u128 i8 i16 i32 i64 i128 usize isize]
    FLOAT_TYPES = %w[f32 f64]

    PUNCT = {
      "(" => :lparen, ")" => :rparen,
      "{" => :lbrace, "}" => :rbrace,
      "[" => :lbracket, "]" => :rbracket,
      "," => :comma, ";" => :semicolon, ":" => :colon,
      "." => :dot,
      "->" => :arrow, "=>" => :arrow,
      ".." => :dotdot, "..=" => :dotdot_eq, "..." => :ellipsis,
      "?" => :question, "!" => :bang, "&" => :amp, "*" => :star,
      "+" => :plus, "-" => :minus, "/" => :slash, "%" => :percent,
      "|" => :pipe, "^" => :caret, "#" => :hash,
      "=" => :eq, "==" => :eq_eq, "!=" => :bang_eq,
      "<" => :lt, "<=" => :lte, ">" => :gt, ">=" => :gte,
      "+=" => :plus_eq, "-=" => :minus_eq, "*=" => :star_eq,
      "/=" => :slash_eq, "%=" => :percent_eq,
      "<<=" => :shl_eq, ">>=" => :shr_eq,
      "&=" => :and_eq, "|=" => :or_eq, "^=" => :xor_eq,
      "&&" => :and_and, "||" => :or_or,
      "<<" => :shl, ">>" => :shr,
    }

    MAX_PUNCT_LEN = PUNCT.keys.map(&:length).max

    def initialize(source, file = "<input>")
      @src = source
      @file = file
      @pos = 0
      @line = 1
      @col = 1
      @tokens = []
    end

    def tokenize
      until eof?
        skip_ws_and_comments
        break if eof?
        @tokens << next_token
      end
      @tokens << Token.new(:eof, nil, @line, @col)
      @tokens
    end

    private

    def eof?
      @pos >= @src.length
    end

    def peek(offset = 0)
      @src[@pos + offset]
    end

    def advance(n = 1)
      n.times do
        c = @src[@pos]
        @pos += 1
        if c == "\n"
          @line += 1
          @col = 1
        else
          @col += 1
        end
      end
    end

    def error(message)
      raise DiagError.new(@file, @line, @col, message)
    end

    def skip_ws_and_comments
      loop do
        c = peek
        if c == "\n" || c == " " || c == "\t" || c == "\r"
          advance
        elsif c == "/" && peek(1) == "/"
          advance(2)
          advance until eof? || peek == "\n"
        elsif c == "/" && peek(1) == "*"
          advance(2)
          closed = false
          until eof?
            if peek == "*" && peek(1) == "/"
              advance(2)
              closed = true
              break
            end
            advance
          end
          error("unterminated block comment") unless closed
        else
          return
        end
      end
    end

    def next_token
      c = peek
      if letter?(c)
        lex_ident_or_string
      elsif digit?(c)
        lex_number
      elsif c == "'"
        lex_char
      elsif c == '"'
        lex_string(:normal)
      elsif PUNCT.key?(c) || punct_start?(c)
        lex_punct
      else
        error("unexpected character #{c.inspect}")
      end
    end

    def punct_start?(c)
      PUNCT.keys.any? { |p| p.start_with?(c) }
    end

    def lex_punct
      line, col = @line, @col
      MAX_PUNCT_LEN.downto(1) do |len|
        chunk = @src[@pos, len]
        if (type = PUNCT[chunk])
          advance(len)
          return Token.new(type, chunk, line, col)
        end
      end
      error("unexpected character #{peek.inspect}")
    end

    def letter?(c)
      c && (c =~ /[A-Za-z_]/)
    end

    def digit?(c)
      c && c =~ /[0-9]/
    end

    def lex_ident_or_string
      line, col = @line, @col
      name = +""
      while letter?(peek) || digit?(peek)
        name << peek
        advance
      end

      case name
      when "true"
        Token.new(:bool, true, line, col)
      when "false"
        Token.new(:bool, false, line, col)
      when "none"
        Token.new(:none, nil, line, col)
      when "null"
        Token.new(:null, nil, line, col)
      else
        if (name == "r" || name == "b" || name == "c") && peek == '"'
          kind = { "r" => :raw, "b" => :byte, "c" => :cstring }[name]
          lex_string(kind, line, col)
        elsif KEYWORDS.key?(name)
          Token.new(KEYWORDS[name], name, line, col)
        else
          Token.new(:ident, name, line, col)
        end
      end
    end

    def lex_number
      line, col = @line, @col
      base = 10
      if peek == "0" && %w[x X b B o O].include?(peek(1))
        prefix = peek(1).downcase
        base = { "x" => 16, "b" => 2, "o" => 8 }[prefix]
        advance(2)
        start = @pos
        while (c = peek) && (c == "_" || digit_in_base?(c, base))
          advance
        end
        digits = @src[start...@pos].delete("_")
        error("invalid #{base == 16 ? 'hex' : base == 2 ? 'binary' : 'octal'} literal") if digits.empty?
        value = digits.to_i(base)
        lex_number_suffix(value, line, col, float: false)
      else
        start = @pos
        while digit?(peek) || peek == "_"
          advance
        end
        is_float = false
        if peek == "." && digit?(peek(1))
          is_float = true
          advance
          while digit?(peek) || peek == "_"
            advance
          end
        end
        raw = @src[start...@pos].delete("_")
        if is_float
          value = raw.to_f
          lex_number_suffix(value, line, col, float: true)
        else
          value = raw.to_i(10)
          lex_number_suffix(value, line, col, float: false)
        end
      end
    end

    def lex_number_suffix(value, line, col, float:)
      suffix = nil
      letters = +""
      while (c = peek) && c =~ /[A-Za-z0-9]/
        letters << c
        advance
      end
      suffix = letters unless letters.empty?

      if suffix
        if float && FLOAT_TYPES.include?(suffix)
          Token.new(:float, [value, suffix], line, col)
        elsif !float && INT_TYPES.include?(suffix)
          Token.new(:int, [value, suffix], line, col)
        else
          error("invalid literal suffix #{suffix.inspect}")
        end
      elsif float
        Token.new(:float, [value, nil], line, col)
      else
        Token.new(:int, [value, nil], line, col)
      end
    end

    def digit_in_base?(c, base)
      d = c.ord
      val = if d >= 48 && d <= 57
              d - 48
            elsif d >= 97 && d <= 122
              d - 87
            elsif d >= 65 && d <= 90
              d - 55
            else
              -1
            end
      val >= 0 && val < base
    end

    def lex_char
      line, col = @line, @col
      advance # opening '
      value = if peek == "\\"
                advance
                lex_escape
              else
                c = peek
                error("unterminated char literal") if c.nil? || c == "'" || c == "\n"
                advance
                c.ord
              end
      error("unterminated char literal") unless peek == "'"
      advance
      Token.new(:char, value, line, col)
    end

    def lex_string(kind, line = nil, col = nil)
      line ||= @line
      col ||= @col
      advance # opening quote
      value = +""
      loop do
        c = peek
        error("unterminated string literal") if c.nil? || c == "\n"
        if c == '"'
          advance
          break
        end
        if c == "\\" && kind != :raw
          advance
          value << lex_escape.chr(Encoding::UTF_8)
        else
          value << c
          advance
        end
      end
      Token.new(:string, [value, kind], line, col)
    end

    def lex_escape
      c = peek
      error("unterminated escape sequence") if c.nil?
      advance
      case c
      when "n" then "\n".ord
      when "t" then "\t".ord
      when "r" then "\r".ord
      when "0" then 0
      when "\\" then "\\".ord
      when '"' then '"'.ord
      when "'" then "'".ord
      when "x"
        hex = +""
        2.times do
          c = peek
          break if c.nil? || !hex_digit?(c)
          hex << c
          advance
        end
        error("\\x escape requires exactly 2 hex digits") unless hex.length == 2
        hex.to_i(16)
      else error("unknown escape sequence \\#{c}")
      end
    end

    def hex_digit?(c)
      c && c =~ /[0-9a-fA-F]/
    end
  end
end
