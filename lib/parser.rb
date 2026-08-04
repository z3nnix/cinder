module Cinder
  class Parser
    include AST

    ASSIGN_OPS = {
      eq: "=", plus_eq: "+=", minus_eq: "-=", star_eq: "*=",
      slash_eq: "/=", percent_eq: "%=", and_eq: "&=",
      or_eq: "|=", xor_eq: "^=", shl_eq: "<<=", shr_eq: ">>=",
    }.freeze

    BINARY_PREC = {
      or_or: 3, and_and: 4,
      pipe: 5, caret: 6, amp: 7,
      eq_eq: 8, bang_eq: 8,
      lt: 9, lte: 9, gt: 9, gte: 9,
      shl: 10, shr: 10,
      plus: 11, minus: 11,
      star: 12, slash: 12, percent: 12,
    }.freeze

    CAST_PREC = 13

    PRIMITIVES = %w[u8 u16 u32 u64 u128 i8 i16 i32 i64 i128 f32 f64 bool usize isize void]

    def initialize(tokens, file = "<input>", reporter = nil)
      @tokens = tokens
      @file = file
      @reporter = reporter
      @pos = 0
    end

    def parse_program
      decls = []
      uses = []
      until at?(:eof)
        tok = peek
        case tok.type
        when :use
          uses << parse_use
        when :export
          advance
          decls << parse_top_decl(exported: true)
        when :const
          decls << parse_const(exported: false)
        when :fn
          decls << parse_fn(exported: false, unsafe: false)
        when :unsafe
          advance
          error("expected `fn` after `unsafe`") unless at?(:fn)
          decls << parse_fn(exported: false, unsafe: true)
        when :extern
          advance
          error("expected `fn` after `extern`") unless at?(:fn)
          decls << parse_fn(exported: false, unsafe: false, extern: true)
        when :struct
          decls << parse_struct(exported: false)
        when :enum
          decls << parse_enum(exported: false)
        when :hash
          target = parse_target_attr
          decls << parse_top_decl(exported: false, target: target)
        when :ident
          case tok.value
          when "static"
            decls << parse_static(exported: false)
          when "export"
            advance
            decls << parse_top_decl(exported: true)
          when "struct"
            decls << parse_struct(exported: false)
          when "static_assert"
            decls << parse_static_assert
          else
            error("unexpected token #{tok.value.inspect} at top level")
          end
        else
          error("unexpected token #{tok.inspect} at top level")
        end
      end
      Program.new(1, 1, decls: decls, uses: uses)
    end

    private

    # helpers

    def peek(n = 0)
      @tokens[@pos + n] || @tokens[-1]
    end

    def at?(type)
      peek.type == type
    end

    def advance
      tok = @tokens[@pos]
      @pos += 1 if @pos < @tokens.length
      tok
    end

    def accept?(type)
      return nil unless at?(type)
      advance
    end

    def expect(type, message = nil)
      return advance if at?(type)
      error(message || "expected `#{TOKEN_NAMES[type] || type}`, found `#{peek.type}`")
    end

    def error(message)
      tok = peek
      raise DiagError.new(@file, tok.line, tok.col, message)
    end

    TOKEN_NAMES = {
      lparen: "(", rparen: ")", lbrace: "{", rbrace: "}",
      lbracket: "[", rbracket: "]", comma: ",", semicolon: ";",
      colon: ":", dot: ".", arrow: "->", eq: "=",
      ident: "identifier", string: "string", int: "integer",
    }.freeze

    def expect_ident(message = "expected identifier")
      tok = expect(:ident, message)
      tok.value
    end

    def expect_semicolon
      expect(:semicolon, "expected `;`")
    end

    def accept_ident?(name)
      return nil unless at?(:ident) && peek.value == name
      advance
    end

    # top-level decls

    def parse_static_assert
      tok = expect(:ident, "expected `static_assert`")
      error("expected `static_assert`") unless tok.value == "static_assert"
      expect(:lparen, "expected `(` after `static_assert`")
      cond = with_no_struct_init { parse_expression }
      expect(:rparen, "expected `)`")
      expect_semicolon
      StaticAssertStmt.new(tok.line, tok.col, cond: cond)
    end

    def parse_top_decl(exported:, target: nil)
      case peek.type
      when :const
        parse_const(exported: exported)
      when :fn
        parse_fn(exported: exported, unsafe: false, target: target)
      when :unsafe
        advance
        parse_fn(exported: exported, unsafe: true, target: target)
      when :extern
        advance
        parse_fn(exported: exported, unsafe: false, extern: true, target: target)
      when :struct
        parse_struct(exported: exported, target: target)
      when :enum
        parse_enum(exported: exported, target: target)
      when :ident
        if peek.value == "static"
          parse_static(exported: exported)
        elsif peek.value == "struct"
          parse_struct(exported: exported, target: target)
        else
          error("unexpected token after attribute/export")
        end
      else
        error("unexpected token after attribute/export")
      end
    end

    def parse_target_attr
      expect(:hash, "expected `#`")
      expect(:lbracket, "expected `[` in attribute")
      name = expect(:ident, "expected attribute name").value
      unless name == "target"
        error("unknown attribute `##[#{name}]`")
      end
      expect(:lparen, "expected `(`")
      str = expect(:string, "expected string in #[target]").value.first
      expect(:rparen, "expected `)`")
      expect(:rbracket, "expected `]`")
      str
    end

    def parse_use
      tok = expect(:use)
      path_tok = expect(:string, "expected module path string")
      expect_semicolon
      UseStmt.new(tok.line, tok.col, path: path_tok.value.first)
    end

    def parse_const(exported:)
      tok = expect(:const)
      name = expect_ident
      type = accept?(:colon) ? parse_type : nil
      expect(:eq, "expected `=` in const")
      value = parse_expression
      expect_semicolon
      ConstDecl.new(tok.line, tok.col, name: name, type: type, value: value, exported: exported)
    end

    def parse_static(exported:)
      tok = expect(:ident)
      name = expect_ident
      type = accept?(:colon) ? parse_type : nil
      expect(:eq, "expected `=` in static")
      init = parse_expression
      section = parse_trailing_section
      expect_semicolon
      StaticDecl.new(tok.line, tok.col, name: name, type: type, init: init, exported: exported, section: section)
    end

    def parse_trailing_section
      return nil unless accept_ident?("section")
      expect(:lparen, "expected `(` after section")
      str = expect(:string, "expected section name string").value.first
      expect(:rparen, "expected `)`")
      str
    end

    def parse_struct(exported:, target: nil)
      tok = expect(:ident, "expected `struct`")
      error("expected `struct`") unless tok.value == "struct"
      name = expect_ident
      fields = []
      expect(:lbrace, "expected `{`")
      until accept?(:rbrace)
        if at?(:eof)
          error("unterminated struct body")
        end
        field_tok = expect(:ident, "expected field name")
        expect(:colon, "expected `:` after field name")
        field_type = parse_type
        fields << StructField.new(field_tok.line, field_tok.col, name: field_tok.value, type: field_type)
        unless accept?(:semicolon) || accept?(:comma)
          error("expected `;` after struct field")
        end
      end
      StructDecl.new(tok.line, tok.col, name: name, fields: fields, exported: exported, target: target)
    end

    def parse_enum(exported:, target: nil)
      tok = expect(:enum)
      name = expect_ident
      variants = []
      expect(:lbrace, "expected `{`")
      until accept?(:rbrace)
        if at?(:eof)
          error("unterminated enum body")
        end
        variant_tok = expect(:ident, "expected variant name")
        variants << EnumVariant.new(variant_tok.line, variant_tok.col, name: variant_tok.value)
        unless accept?(:semicolon) || accept?(:comma)
          error("expected `;` after enum variant")
        end
      end
      EnumDecl.new(tok.line, tok.col, name: name, variants: variants, exported: exported, target: target)
    end

    FN_LEAD_ATTRS = %w[inline naked].freeze
    FN_TRAIL_ATTRS = %w[inline naked section noreturn].freeze

    def parse_fn(exported:, unsafe:, extern: false, target: nil)
      tok = expect(:fn)
      attrs = {}
      if at?(:ident) && FN_LEAD_ATTRS.include?(peek.value)
        attrs[peek.value.to_sym] = true
        advance
      end

      name = expect_ident

      params, variadic = parse_params

      return_type = accept?(:arrow) ? parse_type : nil
      unless return_type
        if at?(:bang) || at?(:question)
          return_type = parse_type
        end
      end

      loop do
        if at?(:ident) && FN_TRAIL_ATTRS.include?(peek.value)
          attr_name = peek.value
          advance
          if attr_name == "section"
            expect(:lparen, "expected `(`")
            str = expect(:string, "expected section name string").value.first
            expect(:rparen, "expected `)`")
            attrs[:section] = str
          else
            attrs[attr_name.to_sym] = true
          end
        else
          break
        end
      end

      body = nil
      if at?(:semicolon)
        error("non-extern function `#{name}` must have a body") unless extern
        advance
      else
        body = parse_block
      end

      FnDecl.new(tok.line, tok.col,
        name: name, params: params, return_type: return_type, body: body,
        unsafe: unsafe, exported: exported,
        inline: attrs[:inline], naked: attrs[:naked], section: attrs[:section],
        target: target, extern: extern, variadic: variadic, noreturn: attrs[:noreturn])
    end

    def parse_params
      expect(:lparen, "expected `(`")
      params = []
      variadic = false
      loop do
        if at?(:rparen)
          advance
          break
        end
        if at?(:eof)
          error("unterminated parameter list")
        end
        if at?(:ellipsis)
          advance
          variadic = true
          expect(:rparen, "expected `)` after `...`")
          break
        end
        name_tok = expect(:ident, "expected parameter name")
        expect(:colon, "expected `:` after parameter name")
        type = parse_type
        params << Param.new(name_tok.line, name_tok.col, name: name_tok.value, type: type)
        if at?(:rparen)
          advance
          break
        end
        accept?(:comma) or error("expected `,` or `)` in parameter list")
      end
      [params, variadic]
    end

    # types

    def parse_type
      tok = peek
      case tok.type
      when :lbracket
        advance
        if accept?(:rbracket)
          elem = parse_type
          SliceType.new(tok.line, tok.col, elem: elem)
        else
          len = parse_expression
          expect(:rbracket, "expected `]` in array type")
          elem = parse_type
          ArrayType.new(tok.line, tok.col, len: len, elem: elem)
        end
      when :star
        advance
        const = false
        volatile = false
        loop do
          if accept?(:const)
            const = true
          elsif accept?(:volatile)
            volatile = true
          else
            break
          end
        end
        elem = parse_type
        PointerType.new(tok.line, tok.col, elem: elem, const: const, volatile: volatile)
      when :question
        advance
        OptionalType.new(tok.line, tok.col, inner: parse_type)
      when :bang
        advance
        ErrorType.new(tok.line, tok.col, inner: parse_type)
      when :fn
        advance
        params = []
        expect(:lparen, "expected `(` after `fn` type")
        unless at?(:rparen)
          loop do
            params << parse_type
            break if accept?(:rparen)
            accept?(:comma) or error("expected `,` or `)` in function type")
            break if accept?(:rparen)
          end
        else
          advance
        end
        ret = accept?(:arrow) ? parse_type : nil
        FunctionType.new(tok.line, tok.col, params: params, ret: ret)
      when :ident
        advance
        if tok.value == "struct"
          NamedType.new(tok.line, tok.col, name: expect_ident)
        elsif PRIMITIVES.include?(tok.value)
          PrimitiveType.new(tok.line, tok.col, name: tok.value)
        else
          NamedType.new(tok.line, tok.col, name: tok.value)
        end
      else
        error("expected type, found `#{tok.type}`")
      end
    end

    def parse_type_parens
      expect(:lparen, "expected `(`")
      t = parse_type
      expect(:rparen, "expected `)`")
      t
    end

    # statements

    def parse_block
      tok = expect(:lbrace, "expected `{`")
      stmts = []
      until accept?(:rbrace)
        if at?(:eof)
          error("unterminated block")
        end
        stmt = parse_statement
        stmts << stmt if stmt
      end
      Block.new(tok.line, tok.col, stmts: stmts)
    end

    def parse_statement
      tok = peek
      case tok.type
      when :semicolon
        advance
        nil
      when :let
        parse_let
      when :if
        parse_if_stmt
      when :while
        parse_while
      when :loop
        parse_loop
      when :for
        parse_for
      when :switch
        parse_switch
      when :return
        parse_return
      when :break
        advance
        expect_semicolon
        BreakStmt.new(tok.line, tok.col)
      when :continue
        advance
        expect_semicolon
        ContinueStmt.new(tok.line, tok.col)
      when :defer
        parse_defer
      when :unsafe
        advance
        block = parse_block
        UnsafeBlock.new(tok.line, tok.col, block: block)
      when :lbrace
        parse_block
      when :ident
        if tok.value == "static_assert"
          parse_static_assert
        else
          parse_expr_or_assign
        end
      else
        parse_expr_or_assign
      end
    end

    def parse_let
      tok = expect(:let)
      mutable = !accept?(:mut).nil?
      name = expect_ident
      type = accept?(:colon) ? parse_type : nil
      expect(:eq, "expected `=` (variables must be initialized)")
      init = parse_expression
      expect_semicolon
      LetStmt.new(tok.line, tok.col, name: name, mutable: mutable, type_annot: type, init: init)
    end

    def with_no_struct_init
      prev = @no_struct_init
      @no_struct_init = true
      yield
    ensure
      @no_struct_init = prev
    end

    def parse_if_stmt
      tok = expect(:if)
      cond = with_no_struct_init { parse_expression }
      then_block = parse_block
      elifs = []
      else_block = nil
      while at?(:else) && peek(1).type == :if
        advance # else
        advance # if
        elif_cond = with_no_struct_init { parse_expression }
        elif_block = parse_block
        elifs << [elif_cond, elif_block]
      end
      if accept?(:else)
        else_block = parse_block
      end
      IfStmt.new(tok.line, tok.col, cond: cond, then_block: then_block, elifs: elifs, else_block: else_block)
    end

    def parse_while
      tok = expect(:while)
      cond = with_no_struct_init { parse_expression }
      body = parse_block
      WhileStmt.new(tok.line, tok.col, cond: cond, body: body)
    end

    def parse_loop
      tok = expect(:loop)
      body = parse_block
      LoopStmt.new(tok.line, tok.col, body: body)
    end

    def parse_for
      tok = expect(:for)
      first = expect_ident
      if accept?(:comma)
        index_var = first
        value_var = expect_ident
      else
        index_var = nil
        value_var = first
      end
      expect(:ident, "expected `in`") unless at?(:ident) && peek.value == "in"
      advance # in
      iterable = with_no_struct_init { parse_expression }
      body = parse_block
      if index_var
        ForIterStmt.new(tok.line, tok.col,
          index_var: index_var, value_var: value_var, iterable: iterable, body: body)
      elsif iterable.is_a?(RangeExpr)
        ForRangeStmt.new(tok.line, tok.col, var: value_var, range: iterable, body: body)
      else
        ForIterStmt.new(tok.line, tok.col,
          index_var: nil, value_var: value_var, iterable: iterable, body: body)
      end
    end

    def parse_switch
      tok = expect(:switch)
      subject = with_no_struct_init { parse_expression }
      cases = []
      else_block = nil
      expect(:lbrace, "expected `{`")
      until accept?(:rbrace)
        if at?(:eof)
          error("unterminated switch body")
        end
        if at?(:else)
          advance
          expect(:arrow, "expected `=>`")
          else_block = parse_switch_body
        else
          pattern = parse_switch_pattern
          expect(:arrow, "expected `=>`")
          body = parse_switch_body
          cases << SwitchCase.new(pattern.line, pattern.col, pattern: pattern, body: body)
        end
      end
      SwitchStmt.new(tok.line, tok.col, subject: subject, cases: cases, else_block: else_block)
    end

    def parse_switch_pattern
      if at?(:dot)
        tok = advance
        name = expect_ident
        return EnumValueExpr.new(tok.line, tok.col, type_name: nil, variant: name)
      end
      parse_expression(1)
    end

    def parse_switch_body
      return parse_block if at?(:lbrace)
      stmt = parse_statement
      tok = stmt || peek
      Block.new(tok.line, tok.col, stmts: stmt ? [stmt] : [])
    end

    def parse_return
      tok = expect(:return)
      value = nil
      unless at?(:semicolon)
        value = parse_expression
      end
      expect_semicolon
      ReturnStmt.new(tok.line, tok.col, value: value)
    end

    def parse_defer
      tok = expect(:defer)
      stmt = parse_statement
      error("expected statement after `defer`") if stmt.nil?
      DeferStmt.new(tok.line, tok.col, stmt: stmt)
    end

    def parse_expr_or_assign
      expr = parse_expression
      tok = peek
      if (op = ASSIGN_OPS[tok.type])
        advance
        value = parse_expression
        expect_semicolon
        return AssignStmt.new(expr.line, expr.col, target: expr, op: op, value: value)
      end
      terminated = false
      if at?(:semicolon)
        advance
        terminated = true
      elsif !at?(:rbrace)
        error("expected `;`")
      end
      ExprStmt.new(expr.line, expr.col, expr: expr, terminated: terminated)
    end

    # expressions

    def parse_expression(min_prec = 1)
      lhs = parse_unary
      loop do
        tok = peek
        case tok.type
        when :as
          break if CAST_PREC < min_prec
          advance
          type = parse_type
          lhs = CastExpr.new(tok.line, tok.col, expr: lhs, type: type)
        when :dotdot, :dotdot_eq
          break if 1 < min_prec
          advance
          rhs = range_end
          lhs = RangeExpr.new(tok.line, tok.col, start: lhs, end_: rhs, inclusive: tok.type == :dotdot_eq)
        when :else
          break if 1 < min_prec
          advance
          block = parse_block
          lhs = OptionalElseExpr.new(tok.line, tok.col, target: lhs, else_block: block)
        else
          prec = BINARY_PREC[tok.type]
          break unless prec && prec >= min_prec
          op = tok.value
          advance
          rhs = parse_expression(prec + 1)
          lhs = BinaryExpr.new(tok.line, tok.col, op: op, lhs: lhs, rhs: rhs)
        end
      end
      lhs
    end

    def range_end
      if %i[semicolon rbracket rparen comma rbrace colon eof].include?(peek.type)
        nil
      else
        parse_expression(2)
      end
    end

    def parse_unary
      tok = peek
      case tok.type
      when :minus
        advance
        UnaryExpr.new(tok.line, tok.col, op: "-", operand: parse_unary)
      when :bang
        advance
        UnaryExpr.new(tok.line, tok.col, op: "!", operand: parse_unary)
      when :amp
        advance
        UnaryExpr.new(tok.line, tok.col, op: "&", operand: parse_unary)
      when :star
        advance
        UnaryExpr.new(tok.line, tok.col, op: "*", operand: parse_unary)
      else
        parse_postfix
      end
    end

    def parse_postfix
      lhs = parse_primary
      loop do
        tok = peek
        case tok.type
        when :lparen
          advance
          args = []
          unless at?(:rparen)
            loop do
              args << parse_expression
              break if accept?(:rparen)
              accept?(:comma) or error("expected `,` or `)` in arguments")
              break if accept?(:rparen)
            end
          else
            advance
          end
          lhs = CallExpr.new(tok.line, tok.col, callee: lhs, args: args)
        when :lbracket
          advance
          lhs = parse_index_or_slice(lhs, tok)
        when :dot
          advance
          field = expect_ident
          lhs = FieldAccessExpr.new(tok.line, tok.col, target: lhs, field: field)
        when :question
          advance
          lhs = ErrorUnwrapExpr.new(tok.line, tok.col, target: lhs)
        else
          break
        end
      end
      lhs
    end

    def parse_index_or_slice(target, tok)
      if at?(:dotdot) || at?(:dotdot_eq)
        advance
        finish = parse_index_end
        expect(:rbracket, "expected `]`")
        return SliceExpr.new(tok.line, tok.col, target: target, start: nil, end_: finish)
      end

      first = parse_expression
      if at?(:dotdot) || at?(:dotdot_eq)
        advance
        finish = parse_index_end
        expect(:rbracket, "expected `]`")
        SliceExpr.new(tok.line, tok.col, target: target, start: first, end_: finish)
      elsif first.is_a?(RangeExpr)
        expect(:rbracket, "expected `]`")
        SliceExpr.new(tok.line, tok.col, target: target, start: first.start, end_: first.end_)
      else
        expect(:rbracket, "expected `]`")
        IndexExpr.new(tok.line, tok.col, target: target, index: first)
      end
    end

    def parse_index_end
      if at?(:rbracket)
        nil
      else
        parse_expression
      end
    end

    def parse_primary
      tok = peek
      case tok.type
      when :int
        advance
        IntLiteral.new(tok.line, tok.col, value: tok.value[0], suffix: tok.value[1])
      when :float
        advance
        FloatLiteral.new(tok.line, tok.col, value: tok.value[0], suffix: tok.value[1])
      when :bool
        advance
        BoolLiteral.new(tok.line, tok.col, value: tok.value)
      when :char
        advance
        CharLiteral.new(tok.line, tok.col, value: tok.value)
      when :string
        advance
        StringLiteral.new(tok.line, tok.col, value: tok.value[0], kind: tok.value[1])
      when :none
        advance
        NoneLiteral.new(tok.line, tok.col)
      when :null
        advance
        NullLiteral.new(tok.line, tok.col)
      when :dot
        advance
        name = expect_ident
        EnumValueExpr.new(tok.line, tok.col, type_name: nil, variant: name)
      when :lparen
        advance
        expr = parse_expression
        expect(:rparen, "expected `)`")
        expr
      when :lbracket
        advance
        elements = []
        repeat = false
        unless at?(:rbracket)
          elements << parse_expression
          if accept?(:semicolon)
            repeat = true
            count = parse_expression
            expect(:rbracket, "expected `]` in array literal")
            ArrayLiteralExpr.new(tok.line, tok.col, elements: elements, repeat: true, repeat_count: count)
          else
            loop do
              break if accept?(:rbracket)
              accept?(:comma) or error("expected `,` or `]` in array literal")
              break if accept?(:rbracket)
              elements << parse_expression
            end
            ArrayLiteralExpr.new(tok.line, tok.col, elements: elements)
          end
        else
          advance
          ArrayLiteralExpr.new(tok.line, tok.col, elements: elements)
        end
      when :if
        parse_if_expr
      when :ident
        parse_ident_primary
      else
        error("unexpected token #{tok.type} in expression")
      end
    end

    def parse_ident_primary
      tok = expect(:ident)
      case tok.value
      when "asm"
        if at?(:lparen)
          advance
          str = expect(:string, "expected asm string").value.first
          if at?(:colon) && peek(1).type == :colon
            error("extended asm syntax is not supported yet")
          end
          expect(:rparen, "expected `)`")
          return AsmExpr.new(tok.line, tok.col, asm_string: str)
        end
      when "sizeof"
        return SizeofExpr.new(tok.line, tok.col, type_node: parse_type_parens)
      when "alignof"
        return AlignofExpr.new(tok.line, tok.col, type_node: parse_type_parens)
      when "offsetof"
        expect(:lparen, "expected `(` after `offsetof`")
        type_node = parse_type
        expect(:comma, "expected `,` in `offsetof`")
        field = expect_ident
        expect(:rparen, "expected `)`")
        return OffsetofExpr.new(tok.line, tok.col, type_node: type_node, field: field)
      end

      if at?(:lbrace) && !@no_struct_init
        advance
        fields = []
        unless at?(:rbrace)
          loop do
            field_tok = expect(:ident, "expected field name")
            value = nil
            if accept?(:colon)
              value = parse_expression
            end
            fields << StructInitField.new(field_tok.line, field_tok.col, name: field_tok.value, value: value)
            break if accept?(:rbrace)
            accept?(:comma) or error("expected `,` or `}` in struct literal")
            break if accept?(:rbrace)
          end
        else
          advance
        end
        return StructInitExpr.new(tok.line, tok.col, type_name: tok.value, fields: fields)
      end

      VarExpr.new(tok.line, tok.col, name: tok.value)
    end

    def parse_if_expr
      tok = expect(:if)
      cond = with_no_struct_init { parse_expression }
      then_block = parse_block
      else_block = nil
      if accept?(:else)
        else_block = at?(:if) ? parse_if_expr : parse_block
      end
      IfExpr.new(tok.line, tok.col, cond: cond, then_block: then_block, else_block: else_block)
    end
  end
end
