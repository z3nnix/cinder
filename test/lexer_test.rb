require "minitest/autorun"
require_relative "../lib/error_reporter"
require_relative "../lib/lexer"

class LexerTest < Minitest::Test
  def tokens(src)
    Cinder::Lexer.new(src).tokenize
  end

  def types(src)
    tokens(src).map(&:type)
  end

  def test_empty_source
    assert_equal [:eof], types("")
  end

  def test_keywords
    src = "as break const continue defer else enum fn for if let loop mut return switch unsafe use while"
    expected = %i[as break const continue defer else enum fn for if let loop mut return switch unsafe use while] + [:eof]
    assert_equal expected, types(src)
  end

  def test_identifiers
    assert_equal %i[ident ident ident eof], types("my_var _temp UartConfig")
  end

  def test_integer_literals
    toks = tokens("42 42u32 0xFF 0b1010 0o755 1_000_000")
    vals = toks[0..5].map(&:value)
    assert_equal [[42, nil], [42, "u32"], [255, nil], [10, nil], [493, nil], [1_000_000, nil]], vals
  end

  def test_integer_suffixes
    %w[u8 u16 u32 u64 u128 i8 i16 i32 i64 i128 usize isize].each do |s|
      tok = tokens("7#{s}").first
      assert_equal [:int, 7, s], [tok.type, *tok.value], "suffix #{s}"
    end
  end

  def test_float_literals
    toks = tokens("3.14 3.14f32")
    assert_equal [[3.14, nil], [3.14, "f32"]], toks[0..1].map(&:value)
  end

  def test_float_suffix
    tok = tokens("2.5f64").first
    assert_equal [:float, 2.5, "f64"], [tok.type, *tok.value]
  end

  def test_bool_and_none
    assert_equal %i[bool bool none eof], types("true false none")
    assert_equal [true, false], tokens("true false")[0..1].map(&:value)
  end

  def test_char_literals
    assert_equal :char, tokens("'A'").first.type
    assert_equal "A".ord, tokens("'A'").first.value
    assert_equal "\n".ord, tokens("'\\n'").first.value
  end

  def test_string_literals
    tok = tokens('"Hello\nWorld"').first
    assert_equal [:string, ["Hello\nWorld", :normal]], [tok.type, tok.value]

    raw = tokens(%q{r"C:\Windows\System32"}).first
    assert_equal [:string, [%q{C:\Windows\System32}, :raw]], [raw.type, raw.value]

    byte = tokens(%q{b"raw bytes"}).first
    assert_equal [:string, ["raw bytes", :byte]], [byte.type, byte.value]

    cstr = tokens(%q{c"Hello\0"}).first
    assert_equal [:string, ["Hello\0", :cstring]], [cstr.type, cstr.value]
  end

  def test_hex_escapes
    tok = tokens(%q{"\x1b[31m"}).first
    assert_equal ["\e[31m", :normal], tok.value

    assert_equal 0x41, tokens(%q{'\x41'}).first.value

    assert_equal 27, tokens(%q{"\x1b"}).first.value.first.ord
  end

  def test_hex_escape_requires_two_digits
    assert_raises(Cinder::DiagError) { Cinder::Lexer.new(%q{"\x"}).tokenize }
    assert_raises(Cinder::DiagError) { Cinder::Lexer.new(%q{"\xZ"}).tokenize }
    assert_raises(Cinder::DiagError) { Cinder::Lexer.new(%q{"\x1"}).tokenize }
  end

  def test_punctuation
    expected = %i[lparen rparen lbrace rbrace lbracket rbracket comma semicolon colon
                  dot arrow dotdot dotdot_eq question bang amp star plus minus slash percent
                  eq eq_eq bang_eq lt lte gt gte plus_eq minus_eq star_eq slash_eq percent_eq
                  shl shr and_eq or_eq xor_eq and_and or_or eof]
    assert_equal expected, types("( ) { } [ ] , ; : . -> .. ..= ? ! & * + - / % = == != < <= > >= += -= *= /= %= << >> &= |= ^= && ||")
  end

  def test_comments
    assert_equal %i[ident ident eof], types("a // comment\nb /* block\ncomment */")
    assert_equal %i[ident eof], types("/* only comment */ x")
  end

  def test_positions
    toks = tokens("let x = 1;\nlet y = 2;")
    assert_equal [1, 1], [toks[0].line, toks[0].col]
    assert_equal [2, 1], [toks[5].line, toks[5].col]
  end

  def test_error_unexpected_char
    err = assert_raises(Cinder::DiagError) { tokens("let @ = 1") }
    assert_match(/unexpected character/, err.message)
  end

  def test_error_unterminated_string
    assert_raises(Cinder::DiagError) { tokens('"abc') }
  end

  def test_error_unterminated_comment
    assert_raises(Cinder::DiagError) { tokens("/* abc") }
  end

  def test_error_bad_suffix
    assert_raises(Cinder::DiagError) { tokens("42foo") }
  end

  def test_error_bad_hex
    assert_raises(Cinder::DiagError) { tokens("0x") }
  end

  def test_range_vs_float
    assert_equal %i[int dotdot int eof], types("0..10")
    assert_equal %i[float eof], types("0.5")
  end

  def test_ranges_half_open
    assert_equal %i[int dotdot_eq int eof], types("1..=10")
  end
end
