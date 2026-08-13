require_relative "layout"

module Cinder
  class Sema
    include AST

    INT_TYPES = %w[u8 u16 u32 u64 u128 i8 i16 i32 i64 i128 usize isize]
    FLOAT_TYPES = %w[f32 f64]

    class ConstError < StandardError; end

    UNKNOWN = Object.new
    def UNKNOWN.inspect
      "<?>"
    end

    Local = Struct.new(:type, :mutable)

    class Context
      attr_accessor :fn, :ret_type, :in_unsafe, :loop_depth, :module_file, :scopes

      def initialize
        @fn = nil
        @ret_type = nil
        @in_unsafe = false
        @loop_depth = 0
        @module_file = nil
        @scopes = []
      end
    end

    def initialize(program, reporter, target: "x86_64")
      @program = program
      @reporter = reporter
      @target = target
      @target_cfg = Targets[target]
      @globals = {}
      @fns = {}
      @structs = {}
      @enums = {}
      @consts = {}
      @statics = {}
      @const_values = {}
      @const_types = {}
      @const_evaluating = {}
      @statics_type = {}
      @statics_value = {}
      @expr_type = {}
      @layout = Layout.new(self)
      @static_asserts = []
    end

    def check
      collect_decls
      resolve_all_types
      check_main_signature
      check_static_asserts
      check_bodies
    end

    def check_main_signature
      m = @fns["main"]
      return unless m
      return if m.params.empty? || main_signature?(m)
      report(m, "unsupported main signature: expected `fn main()`, `fn main() -> i32`, " \
                "`fn main(argc: i32, argv: **u8)`, or `fn main(argc: i32, argv: **u8) -> i32`")
    end

    def main_signature?(m)
      return false unless m.params.length == 2
      p0, p1 = m.params
      return false unless p0.type.is_a?(PrimitiveType) && p0.type.name == "i32"
      return false unless p1.type.is_a?(PointerType) && p1.type.elem.is_a?(PointerType)
      true
    end

    private

    # pass 1

    def collect_decls
      @program.decls.each do |decl|
        next unless target_ok?(decl)
        if decl.is_a?(StaticAssertStmt)
          @static_asserts << decl
          next
        end
        if @globals.key?(decl.name)
          report(decl, "duplicate definition of `#{decl.name}`")
          next
        end
        @globals[decl.name] = decl
        case decl
        when FnDecl then @fns[decl.name] = decl
        when StructDecl then @structs[decl.name] = decl
        when EnumDecl then @enums[decl.name] = decl
        when ConstDecl then @consts[decl.name] = decl
        when StaticDecl then @statics[decl.name] = decl
        end
      end
    end

    def check_static_asserts
      @static_asserts.each { |sa| check_static_assert(sa, Context.new) }
    end

    def target_ok?(decl)
      return true unless decl.respond_to?(:target)
      decl.target.nil? || decl.target == @target
    end

    def resolve_all_types
      @structs.each_value do |s|
        seen = {}
        s.fields.each do |f|
          report(f, "duplicate field `#{f.name}` in struct `#{s.name}`") if seen[f.name]
          seen[f.name] = true
          f.type = resolve_type(f.type, s.module_file)
        end
      end
      @enums.each_value do |e|
        seen = {}
        e.variants.each do |v|
          report(v, "duplicate variant `#{v.name}` in enum `#{e.name}`") if seen[v.name]
          seen[v.name] = true
        end
      end
      @consts.each_value { |c| check_const(c) }
      @statics.each_value do |s|
        @statics_type[s.name] = if s.type
                                  s.type = resolve_type(s.type, s.module_file)
                                else
                                  infer_const_type(s.init)
                                end
      end
      @fns.each_value do |f|
        f.params.each { |p| p.type = resolve_type(p.type, f.module_file) }
        f.return_type = resolve_type(f.return_type, f.module_file) if f.return_type
      end
    end

    def check_const(c)
      eval_const_decl(c)
      t = c.type ? resolve_type(c.type, c.module_file) : (@const_types[c.name] || UNKNOWN)
      @const_types[c.name] = t
      inferred = infer_const_type(c.value)
      return unless c.type
      unless compatible(inferred, t, c.value, nil)
        report(c, "type mismatch in const `#{c.name}`: expected #{type_name(t)}, found #{type_name(inferred)}")
      end
    end

    def resolve_type(t, module_file)
      case t
      when PrimitiveType
        if t.name == "void"
          report(t, "type `void` is only allowed as a function return type", module_file)
          UNKNOWN
        else
          t
        end
      when NamedType
        decl = @structs[t.name] || @enums[t.name]
        if decl.nil?
          report(t, "unknown type `#{t.name}`", module_file)
          UNKNOWN
        else
          unless module_file.nil? || decl.exported || decl.module_file == module_file
            report(t, "type `#{t.name}` is private to its module", module_file)
          end
          t.resolved = decl
          t
        end
      when PointerType
        if void_type?(t.elem)
          t
        else
          t.elem = resolve_type(t.elem, module_file)
          t
        end
      when ArrayType
        t.elem = resolve_type(t.elem, module_file)
        begin
          len = eval_const(t.len, module_file)
          unless len.is_a?(Integer)
            report(t, "array length must be a constant integer", module_file)
            t.len_value = nil
          else
            report(t, "array length must be non-negative", module_file) if len < 0
            t.len_value = len
          end
        rescue ConstError => e
          report(t, "invalid array length: #{e.message}", module_file)
          t.len_value = nil
        end
        t
      when SliceType
        t.elem = resolve_type(t.elem, module_file)
        if void_type?(t.elem)
          report(t, "invalid element type void", module_file)
          t.elem = UNKNOWN
        end
        t
      when OptionalType, ErrorType
        t.inner = resolve_type(t.inner, module_file)
        if void_type?(t.inner)
          report(t, "invalid element type void", module_file)
          t.inner = UNKNOWN
        end
        t
      when FunctionType
        t.params = t.params.map { |p| resolve_type(p, module_file) }
        if t.ret
          if void_type?(t.ret)
            t.ret = nil
          else
            t.ret = resolve_type(t.ret, module_file)
          end
        end
        t
      else
        UNKNOWN
      end
    end

    # const evaluation 

    def eval_const_decl(decl)
      return @const_values[decl.name] if @const_values.key?(decl.name)
      if @const_evaluating[decl.name]
        report(decl, "circular constant definition involving `#{decl.name}`")
        return 0
      end
      @const_evaluating[decl.name] = true
      begin
        value = eval_const(decl.value, decl.module_file)
      rescue ConstError => e
        report(decl, "invalid constant expression: #{e.message}")
        value = 0
      end
      @const_evaluating.delete(decl.name)
      @const_values[decl.name] = value
      @const_types[decl.name] ||= infer_const_type(decl.value)
      value
    end

    def eval_const(node, module_file)
      case node
      when IntLiteral then node.value
      when FloatLiteral then node.value
      when CharLiteral then node.value
      when BoolLiteral then node.value
      when VarExpr
        decl = @consts[node.name]
        raise ConstError, "`#{node.name}` is not a constant" if decl.nil?
        eval_const_decl(decl)
      when UnaryExpr
        v = eval_const(node.operand, module_file)
        case node.op
        when "-" then -v
        when "!" then !v
        else raise ConstError, "unsupported unary operator `#{node.op}`"
        end
      when BinaryExpr
        a = eval_const(node.lhs, module_file)
        b = eval_const(node.rhs, module_file)
        apply_const_op(node.op, a, b)
      when CastExpr
        v = eval_const(node.expr, module_file)
        apply_const_cast(v, node.type, node)
      when ArrayLiteralExpr
        if node.repeat
          count = eval_const(node.repeat_count, module_file)
          raise ConstError, "array length must be an integer" unless count.is_a?(Integer)
          raise ConstError, "array length must be non-negative" if count < 0
          [eval_const(node.elements[0], module_file)] * count
        else
          node.elements.map { |e| eval_const(e, module_file) }
        end
      when SizeofExpr
        t = resolve_type(node.type_node, module_file)
        raise ConstError, "cannot compute the size of an invalid type" if t == UNKNOWN
        node.value = @layout.size(t)
        node.value
      when AlignofExpr
        t = resolve_type(node.type_node, module_file)
        raise ConstError, "cannot compute the alignment of an invalid type" if t == UNKNOWN
        node.value = @layout.align(t)
        node.value
      when OffsetofExpr
        t = resolve_type(node.type_node, module_file)
        raise ConstError, "cannot compute the offset of an invalid type" if t == UNKNOWN
        raise ConstError, "offsetof requires a struct type" unless struct_type?(t)
        off = @layout.field_offset(t.resolved, node.field)
        raise ConstError, "struct has no field `#{node.field}`" if off.nil?
        node.value = off
        off
      else
        raise ConstError, "not a constant expression"
      end
    end

    def apply_const_cast(v, type, node)
      t = resolve_type(type, node.module_file)
      return v if t == UNKNOWN
      unless t.is_a?(PrimitiveType)
        return v
      end
      case t.name
      when "bool" then !(v == 0 || v == 0.0)
      when "f32", "f64" then v.to_f
      when "i8", "i16", "i32", "i64", "i128", "u8", "u16", "u32", "u64", "u128", "usize", "isize"
        v.is_a?(Float) ? v.to_i : v
      else v
      end
    end

    def apply_const_op(op, a, b)
      case op
      when "+" then a + b
      when "-" then a - b
      when "*" then a * b
      when "/"
        raise ConstError, "division by zero" if b == 0
        a / b
      when "%"
        raise ConstError, "division by zero" if b == 0
        a % b
      when "<<" then a << b
      when ">>" then a >> b
      when "&" then a & b
      when "|" then a | b
      when "^" then a ^ b
      when "==" then a == b
      when "!=" then a != b
      when "<" then a < b
      when "<=" then a <= b
      when ">" then a > b
      when ">=" then a >= b
      when "&&" then a && b
      when "||" then a || b
      else raise ConstError, "unsupported operator `#{op}`"
      end
    end

    def infer_const_type(node)
      case node
      when IntLiteral then PrimitiveType.new(node.line, node.col, name: node.suffix || "i32")
      when FloatLiteral then PrimitiveType.new(node.line, node.col, name: node.suffix || "f64")
      when CharLiteral then PrimitiveType.new(node.line, node.col, name: "i32")
      when BoolLiteral then PrimitiveType.new(node.line, node.col, name: "bool")
      when VarExpr then @const_types[node.name] || UNKNOWN
      when UnaryExpr then node.op == "-" ? infer_const_type(node.operand) : UNKNOWN
      when CastExpr then resolve_type(node.type, nil)
      when SizeofExpr, AlignofExpr, OffsetofExpr then PrimitiveType.new(node.line, node.col, name: "usize")
      when BinaryExpr
        a = infer_const_type(node.lhs)
        b = infer_const_type(node.rhs)
        if float_type?(a) || float_type?(b)
          PrimitiveType.new(node.line, node.col, name: "f64")
        else
          PrimitiveType.new(node.line, node.col, name: "i32")
        end
      when ArrayLiteralExpr
        if node.repeat
          elem = node.elements.empty? ? UNKNOWN : infer_const_type(node.elements.first)
          len = begin
            v = eval_const(node.repeat_count, node.module_file)
            v.is_a?(Integer) ? v : nil
          rescue ConstError
            nil
          end
          node.repeat_len = len
          ArrayType.new(node.line, node.col, len: node, elem: elem, len_value: len)
        else
          elem = node.elements.empty? ? UNKNOWN : infer_const_type(node.elements.first)
          ArrayType.new(node.line, node.col, len: node, elem: elem, len_value: node.elements.length)
        end
      else UNKNOWN
      end
    end

    # type helpers

    def bool_type
      PrimitiveType.new(0, 0, name: "bool")
    end

    def void_type?(t)
      t.is_a?(PrimitiveType) && t.name == "void"
    end

    INT_RANK = {
      "u8" => 1, "u16" => 2, "u32" => 3, "u64" => 4, "u128" => 5, "usize" => 5,
      "i8" => 1, "i16" => 2, "i32" => 3, "i64" => 4, "i128" => 5, "isize" => 5,
    }.freeze

    INT_BITS = {
      "u8" => 8, "u16" => 16, "u32" => 32, "u64" => 64, "u128" => 128,
      "i8" => 8, "i16" => 16, "i32" => 32, "i64" => 64, "i128" => 128,
    }.freeze

    def signed?(name)
      name.start_with?("i")
    end

    def int_rank(name)
      case name
      when "usize", "isize" then @target_cfg[:usize_rank]
      else INT_RANK[name] || 0
      end
    end

    def int_type?(t)
      t.is_a?(PrimitiveType) && INT_TYPES.include?(t.name)
    end

    def float_type?(t)
      t.is_a?(PrimitiveType) && FLOAT_TYPES.include?(t.name)
    end

    def numeric_type?(t)
      int_type?(t) || float_type?(t)
    end

    def enum_type?(t)
      t.is_a?(NamedType) && t.resolved.is_a?(EnumDecl)
    end

    def struct_type?(t)
      t.is_a?(NamedType) && t.resolved.is_a?(StructDecl)
    end

    def pointer_qualifiers(t)
      quals = +"*"
      quals << "const " if t.const
      quals << "volatile " if t.volatile
      quals
    end

    def type_name(t)
      case t
      when PrimitiveType then t.name
      when NamedType then t.name
      when ArrayType then "[#{t.len_value || '?'}]#{type_name(t.elem)}"
      when SliceType then "[]#{type_name(t.elem)}"
      when PointerType then "#{pointer_qualifiers(t)}#{type_name(t.elem)}"
      when OptionalType then "?#{type_name(t.inner)}"
      when ErrorType then "!#{type_name(t.inner)}"
      when FunctionType then "fn(#{t.params.map { |p| type_name(p) }.join(', ')})#{t.ret ? " -> #{type_name(t.ret)}" : ''}"
      when nil then "void"
      when UNKNOWN then "<?>"
      else t.inspect
      end
    end

    def equal(a, b)
      return true if a.equal?(b)
      return false if a == UNKNOWN || b == UNKNOWN
      case a
      when PrimitiveType then b.is_a?(PrimitiveType) && a.name == b.name
      when NamedType
        b.is_a?(NamedType) && a.name == b.name && a.resolved && a.resolved.equal?(b.resolved)
      when ArrayType then b.is_a?(ArrayType) && a.len_value == b.len_value && equal(a.elem, b.elem)
      when SliceType then b.is_a?(SliceType) && equal(a.elem, b.elem)
      when PointerType then b.is_a?(PointerType) && (a.const ? true : false) == (b.const ? true : false) && (a.volatile ? true : false) == (b.volatile ? true : false) && equal(a.elem, b.elem)
      when OptionalType then b.is_a?(OptionalType) && equal(a.inner, b.inner)
      when ErrorType then b.is_a?(ErrorType) && equal(a.inner, b.inner)
      when FunctionType
        b.is_a?(FunctionType) &&
          a.params.length == b.params.length &&
          a.params.zip(b.params).all? { |x, y| equal(x, y) } &&
          fn_ret_equal(a.ret, b.ret)
      else false
      end
    end

    def fn_ret_equal(a, b)
      return true if a.nil? && b.nil?
      !a.nil? && !b.nil? && equal(a, b)
    end

    def compatible(actual, expected, node, ctx)
      if (lit = literal_int_value(node))
        return true if int_literal_fits_ctx?(lit, expected, node, ctx)
      end

      return true if equal(actual, expected)
      return true if actual == UNKNOWN || expected == UNKNOWN

      if actual.is_a?(PointerType) && expected.is_a?(PointerType) &&
         void_type?(expected.elem) && !void_type?(actual.elem)
        return true
      end

      case node
      when IntLiteral
        return true if float_type?(expected)
        return true if expected.is_a?(OptionalType) && float_type?(expected.inner)
        return true if expected.is_a?(ErrorType) && float_type?(expected.inner)
      when FloatLiteral
        return true if float_type?(expected)
        return true if expected.is_a?(OptionalType) && float_type?(expected.inner)
        return true if expected.is_a?(ErrorType) && float_type?(expected.inner)
      when CharLiteral
        return true if int_type?(expected)
        return true if expected.is_a?(OptionalType) && int_type?(expected.inner)
        return true if expected.is_a?(ErrorType) && int_type?(expected.inner)
      when BoolLiteral
        return true if expected.is_a?(PrimitiveType) && expected.name == "bool"
      when NoneLiteral
        return true if expected.is_a?(OptionalType) || expected.is_a?(ErrorType)
      when NullLiteral
        return true if expected.is_a?(PointerType) || expected.is_a?(FunctionType)
      when StringLiteral
        return true if equal(string_literal_type(node), expected)
      when ArrayLiteralExpr
        if node.repeat
          return true if expected.is_a?(ArrayType) && node.repeat_len == expected.len_value
        else
          return true if expected.is_a?(ArrayType) && node.elements.length == expected.len_value
        end
      when VarExpr
        if @consts.key?(node.name) && numeric_type?(expected) && numeric_type?(actual)
          return true
        end
      end

      # lossless integer widening (u8->u16->u32->u64, i8->i32, etc.)
      if int_type?(actual) && int_type?(expected)
        if signed?(actual.name) == signed?(expected.name) && int_rank(actual.name) <= int_rank(expected.name)
          return true
        end
      end

      if expected.is_a?(OptionalType)
        return true if compatible(actual, expected.inner, node, ctx)
      end
      if expected.is_a?(ErrorType)
        return true if enum_type?(actual)
        return true if compatible(actual, expected.inner, node, ctx)
      end
      false
    end

    def unify_numeric(node, a, b, an, bn, ctx)
      return a if equal(a, b)
      return a if a == UNKNOWN
      return b if b == UNKNOWN
      unless numeric_type?(a) && numeric_type?(b)
        mismatch(node, a, b, ctx)
        return UNKNOWN
      end
      if float_type?(a) && int_type?(b)
        return int_adaptable?(bn) ? a : mismatch(node, a, b, ctx)
      end
      if int_type?(a) && float_type?(b)
        return int_adaptable?(an) ? b : mismatch(node, a, b, ctx)
      end
      if float_type?(a) && float_type?(b)
        return a
      end
      return a if int_adaptable?(bn)
      return b if int_adaptable?(an)
      mismatch(node, a, b, ctx)
    end

    def mismatch(node, a, b, ctx)
      report(node, "type mismatch: cannot combine #{type_name(a)} and #{type_name(b)}", ctx && ctx.module_file)
      UNKNOWN
    end

    def int_adaptable?(node)
      return false if node.is_a?(FloatLiteral)
      return true if node.is_a?(IntLiteral) || node.is_a?(CharLiteral)
      if node.is_a?(UnaryExpr) && node.op == "-" && node.operand.is_a?(IntLiteral)
        return true
      end
      if node.is_a?(VarExpr) && @consts.key?(node.name)
        return int_type?(@const_types[node.name])
      end
      false
    end

    def int_literal_type(node, expected)
      if node.suffix
        return PrimitiveType.new(node.line, node.col, name: node.suffix)
      end
      v = node.value
      if expected.is_a?(PrimitiveType) && int_type?(expected)
        return expected if int_literal_fits?(v, expected)
      end
      if v >= -2147483648 && v <= 2147483647
        PrimitiveType.new(node.line, node.col, name: "i32")
      elsif v >= -9223372036854775808 && v <= 9223372036854775807
        PrimitiveType.new(node.line, node.col, name: "i64")
      elsif v >= 0 && v <= 18446744073709551615
        PrimitiveType.new(node.line, node.col, name: "u64")
      elsif v >= -170141183460469231731687303715884105728 &&
            v <= 170141183460469231731687303715884105727
        PrimitiveType.new(node.line, node.col, name: "i128")
      else
        PrimitiveType.new(node.line, node.col, name: "u128")
      end
    end

    def literal_int_value(node)
      return node.value if node.is_a?(IntLiteral)
      if node.is_a?(UnaryExpr) && node.op == "-" && node.operand.is_a?(IntLiteral)
        return -node.operand.value
      end
      nil
    end

    def int_literal_fits_ctx?(value, expected, node, ctx)
      if int_type?(expected)
        return true if int_literal_fits?(value, expected)
        report(node, "integer literal #{value} does not fit in #{type_name(expected)}", ctx && ctx.module_file)
        return true
      end
      if expected.is_a?(OptionalType) && int_type?(expected.inner)
        return true if int_literal_fits?(value, expected.inner)
        report(node, "integer literal #{value} does not fit in #{type_name(expected.inner)}", ctx && ctx.module_file)
        return true
      end
      if expected.is_a?(ErrorType) && int_type?(expected.inner)
        return true if int_literal_fits?(value, expected.inner)
        report(node, "integer literal #{value} does not fit in #{type_name(expected.inner)}", ctx && ctx.module_file)
        return true
      end
      false
    end

    def int_literal_fits?(value, t)
      return false unless int_type?(t)
      bits = INT_BITS[t.name]
      bits = @target_cfg[:ptr_bits] if (t.name == "usize" || t.name == "isize") && bits.nil?
      return false unless bits
      if signed?(t.name)
        min = -(1 << (bits - 1))
        max = (1 << (bits - 1)) - 1
      else
        min = 0
        max = (1 << bits) - 1
      end
      value >= min && value <= max
    end

    def float_adaptable?(node)
      return true if node.is_a?(FloatLiteral) || node.is_a?(IntLiteral)
      if node.is_a?(VarExpr) && @consts.key?(node.name)
        return numeric_type?(@const_types[node.name])
      end
      false
    end

    def string_literal_type(node)
      if node.kind == :cstring
        PointerType.new(node.line, node.col, elem: PrimitiveType.new(node.line, node.col, name: "u8"), const: false)
      else
        SliceType.new(node.line, node.col, elem: PrimitiveType.new(node.line, node.col, name: "u8"))
      end
    end

    def struct_field(decl, name)
      decl.fields.find { |f| f.name == name }
    end

    def enum_has_variant?(decl, name)
      decl.variants.any? { |v| v.name == name }
    end

    # pass 2

    def check_bodies
      @statics.each_value { |s| check_static(s) }
      @fns.each_value { |decl| check_fn(decl) }
    end

    def check_static(s)
      value = begin
        eval_const(s.init, s.module_file)
      rescue ConstError => e
        report(s, "invalid static initializer: #{e.message}")
        nil
      end
      @statics_value[s.name] = value
      t = @statics_type[s.name] || UNKNOWN
      it = infer_const_type(s.init)
      ctx = Context.new
      ctx.module_file = s.module_file
      unless compatible(it, t, s.init, ctx)
        report(s, "type mismatch in static `#{s.name}`: expected #{type_name(t)}, found #{type_name(it)}")
      end
    end

    def check_fn(decl)
      return unless decl.body
      ctx = Context.new
      ctx.fn = decl
      ctx.ret_type = decl.return_type ? resolve_type(decl.return_type, decl.module_file) : nil
      ctx.in_unsafe = decl.unsafe
      ctx.module_file = decl.module_file
      stmts = decl.body.stmts
      with_scope(ctx) do
        decl.params.each { |p| define_var(p.name, p.type, true, ctx) }
        stmts.each_with_index do |s, i|
          if i == stmts.length - 1 && s.is_a?(ExprStmt) && !s.terminated
            check_implicit_return(s, ctx)
          else
            check_stmt(s, ctx)
          end
        end
      end
      if ctx.ret_type && stmts.empty?
        report(decl, "function `#{decl.name}` must return a value of type #{type_name(ctx.ret_type)}")
      end
    end

    def check_implicit_return(s, ctx)
      vt = infer_expr(s.expr, ctx, expected: ctx.ret_type)
      return if vt.nil?
      if ctx.ret_type.nil?
        report(s, "void function cannot return a value; add `;` or remove the trailing expression")
        return
      end
      unless compatible(vt, ctx.ret_type, s.expr, ctx)
        report(s, "type mismatch in implicit return: expected #{type_name(ctx.ret_type)}, found #{type_name(vt)}")
      end
    end

    def check_stmt(node, ctx)
      case node
      when Block
        with_scope(ctx) { node.stmts.each { |s| check_stmt(s, ctx) } }
      when LetStmt then check_let(node, ctx)
      when AssignStmt then check_assign(node, ctx)
      when IfStmt
        check_cond(node.cond, ctx)
        check_block(node.then_block, ctx)
        node.elifs.each do |cond, block|
          check_cond(cond, ctx)
          check_block(block, ctx)
        end
        check_block(node.else_block, ctx) if node.else_block
      when WhileStmt
        check_cond(node.cond, ctx)
        with_loop(ctx) { check_block(node.body, ctx) }
      when LoopStmt
        with_loop(ctx) { check_block(node.body, ctx) }
      when ForRangeStmt then check_for_range(node, ctx)
      when ForIterStmt then check_for_iter(node, ctx)
      when SwitchStmt then check_switch(node, ctx)
      when ReturnStmt then check_return(node, ctx)
      when BreakStmt
        report(node, "`break` outside of a loop", ctx.module_file) unless ctx.loop_depth > 0
      when ContinueStmt
        report(node, "`continue` outside of a loop", ctx.module_file) unless ctx.loop_depth > 0
      when DeferStmt
        check_stmt(node.stmt, ctx)
      when UnsafeBlock
        with_unsafe(ctx) { check_stmt(node.block, ctx) }
      when AsmStmt
        report(node, "asm requires an unsafe block", ctx.module_file) unless ctx.in_unsafe
      when StaticAssertStmt
        check_static_assert(node, ctx)
      when ExprStmt
        infer_expr(node.expr, ctx)
      end
    end

    def check_static_assert(node, ctx)
      value = begin
        eval_const(node.cond, ctx.module_file)
      rescue ConstError => e
        report(node, "static_assert requires a constant expression: #{e.message}", ctx.module_file)
        return
      end
      return if value.is_a?(Integer) && value != 0
      return if value == true
      report(node, "static_assert failed", ctx.module_file)
    end

    def check_block(block, ctx)
      with_scope(ctx) { block.stmts.each { |s| check_stmt(s, ctx) } }
    end

    def check_cond(node, ctx)
      t = infer_expr(node, ctx)
      unless equal(t, bool_type) || t == UNKNOWN
        report(node, "condition must be bool, found #{type_name(t)}", ctx.module_file)
      end
    end

    def check_for_range(node, ctx)
      range = node.range
      if range.end_.nil?
        report(range, "for range must have an end", ctx.module_file)
        return
      end
      t = check_range(range, ctx)
      with_scope(ctx) do
        define_var(node.var, t, false, ctx) if t
        with_loop(ctx) { check_block(node.body, ctx) }
      end
    end

    def check_range(range, ctx)
      st = infer_expr(range.start, ctx)
      et = infer_expr(range.end_, ctx)
      if st == UNKNOWN
        return et
      end
      if et == UNKNOWN
        return st
      end
      if numeric_type?(st) && numeric_type?(et)
        u = unify_numeric(range, st, et, range.start, range.end_, ctx)
        return u == UNKNOWN ? (st || et) : u
      end
      report(range, "range bounds must be numeric, found #{type_name(st)} and #{type_name(et)}", ctx.module_file)
      UNKNOWN
    end

    def check_for_iter(node, ctx)
      it = infer_expr(node.iterable, ctx)
      elem = case it
             when SliceType then it.elem
             when ArrayType then it.elem
             when UNKNOWN then UNKNOWN
             else
               report(node.iterable, "cannot iterate over a value of type #{type_name(it)}", ctx.module_file)
               UNKNOWN
             end
      with_scope(ctx) do
        define_var(node.index_var, usize_type(node), false, ctx) if node.index_var
        define_var(node.value_var, elem, false, ctx)
        with_loop(ctx) { check_block(node.body, ctx) }
      end
    end

    def check_switch(node, ctx)
      st = infer_expr(node.subject, ctx)
      enum = enum_type?(st) ? st : nil
      unless enum || int_type?(st) || st == UNKNOWN
        report(node.subject, "switch subject must be an integer or enum, found #{type_name(st)}", ctx.module_file)
      end
      seen = {}
      node.cases.each do |c|
        check_switch_pattern(c.pattern, enum, st, seen, ctx)
        check_block(c.body, ctx)
      end
      check_block(node.else_block, ctx) if node.else_block
    end

    def check_switch_pattern(pat, enum, st, seen, ctx)
      case pat
      when RangeExpr
        if enum
          report(pat, "range patterns are not allowed on enums", ctx.module_file)
        else
          rt = check_range(pat, ctx)
          report(pat, "range pattern bounds must be integers", ctx.module_file) if rt != UNKNOWN && !int_type?(rt)
        end
      when EnumValueExpr
        unless enum
          report(pat, "enum pattern requires an enum subject", ctx.module_file)
        else
          infer_enum_value(pat, ctx, enum)
        end
        key = [:enum, pat.variant]
        report(pat, "duplicate switch case", ctx.module_file) if seen[key]
        seen[key] = true
      when FieldAccessExpr
        if enum && pat.target.is_a?(VarExpr) && @enums.key?(pat.target.name)
          t = infer_field(pat, ctx)
          unless equal(t, enum)
            report(pat, "switch pattern must be a variant of the subject enum", ctx.module_file)
          end
          key = [:enum, pat.field]
          report(pat, "duplicate switch case", ctx.module_file) if seen[key]
          seen[key] = true
        elsif enum
          report(pat, "invalid enum pattern", ctx.module_file)
        else
          pt = infer_expr(pat, ctx)
          report(pat, "switch pattern must be an integer literal", ctx.module_file) unless int_type?(pt) || pt == UNKNOWN
        end
      else
        pt = infer_expr(pat, ctx)
        if enum
          unless compatible(pt, enum, pat, ctx)
            report(pat, "switch pattern must be a variant of the subject enum", ctx.module_file)
          end
        elsif pt != UNKNOWN && !int_type?(pt)
          report(pat, "switch pattern must be an integer literal, found #{type_name(pt)}", ctx.module_file)
        end
        key = case pat
              when IntLiteral then [:int, pat.value]
              when FloatLiteral then [:float, pat.value]
              end
        if key
          report(pat, "duplicate switch case", ctx.module_file) if seen[key]
          seen[key] = true
        end
      end
    end

    def check_return(node, ctx)
      rt = ctx.ret_type
      if node.value.nil?
        unless rt.nil?
          report(node, "this function must return a value of type #{type_name(rt)}", ctx.module_file)
        end
        return
      end
      if rt.nil?
        infer_expr(node.value, ctx)
        report(node, "void function cannot return a value", ctx.module_file)
        return
      end
      vt = infer_expr(node.value, ctx, expected: rt)
      return if vt.nil?
      unless compatible(vt, rt, node.value, ctx)
        report(node, "type mismatch in return: expected #{type_name(rt)}, found #{type_name(vt)}", ctx.module_file)
      end
    end

    def check_let(node, ctx)
      annot = node.type_annot ? resolve_type(node.type_annot, ctx.module_file) : nil
      it = infer_expr(node.init, ctx, expected: annot)
      if it.nil?
        report(node.init, "cannot initialize `#{node.name}` with a void value", ctx.module_file)
        return
      end
      t = annot || it
      if annot.nil?
        if it == UNKNOWN
          return # error already reported
        end
      elsif !compatible(it, annot, node.init, ctx)
        report(node, "type mismatch for `#{node.name}`: expected #{type_name(annot)}, found #{type_name(it)}", ctx.module_file)
      end
      define_var(node.name, t, node.mutable, ctx)
    end

    def check_assign(node, ctx)
      target = node.target
      tt = infer_expr(target, ctx)
      if tt.nil?
        report(target, "cannot assign to a void value", ctx.module_file)
        return
      end
      report(target, "cannot assign to this value (it is not mutable)", ctx.module_file) unless writable?(target, ctx)
      vt = infer_expr(node.value, ctx, expected: tt)
      if vt.nil?
        report(node.value, "cannot assign a void value", ctx.module_file)
        return
      end
      unless compatible(vt, tt, node.value, ctx)
        report(node, "type mismatch in assignment: expected #{type_name(tt)}, found #{type_name(vt)}", ctx.module_file)
      end
    end

    def writable?(target, ctx)
      case target
      when VarExpr
        local = lookup_var(target.name, ctx)
        return local.mutable if local
        return true if @statics.key?(target.name)
        false
      when FieldAccessExpr
        t = infer_expr(target.target, ctx)
        if t.is_a?(PointerType)
          !t.const
        else
          writable?(target.target, ctx)
        end
      when IndexExpr
        t = infer_expr(target.target, ctx)
        if t.is_a?(PointerType)
          ctx.in_unsafe
        else
          writable?(target.target, ctx)
        end
      when UnaryExpr
        target.op == "*"
      else
        false
      end
    end

    # expressions

    def infer_expr(node, ctx, expected: nil)
      if expected.nil? && @expr_type.key?(node)
        return @expr_type[node]
      end
      t = infer_expr_unmemoized(node, ctx, expected)
      node.sema_type = t if node.is_a?(Expr)
      node.sema_expected = expected if expected
      if expected.nil?
        @expr_type[node] = t
      end
      t
    end

    def infer_expr_unmemoized(node, ctx, expected)
      case node
      when IntLiteral
        int_literal_type(node, expected)
      when FloatLiteral
        PrimitiveType.new(node.line, node.col, name: node.suffix || "f64")
      when BoolLiteral
        bool_type
      when CharLiteral
        PrimitiveType.new(node.line, node.col, name: "i32")
      when StringLiteral
        string_literal_type(node)
      when NoneLiteral
        if expected.is_a?(OptionalType) || expected.is_a?(ErrorType)
          expected
        else
          report(node, "cannot infer type of `none`; annotate the type", ctx && ctx.module_file)
          UNKNOWN
        end
      when NullLiteral
        if expected.is_a?(PointerType) || expected.is_a?(FunctionType)
          expected
        else
          report(node, "cannot infer type of `null`; annotate the type", ctx && ctx.module_file)
          UNKNOWN
        end
      when ArrayLiteralExpr
        infer_array_literal(node, ctx, expected)
      when VarExpr
        infer_var(node, ctx)
      when UnaryExpr
        infer_unary(node, ctx)
      when BinaryExpr
        infer_binary(node, ctx)
      when CastExpr
        infer_cast(node, ctx)
      when CallExpr
        infer_call(node, ctx)
      when IndexExpr
        infer_index(node, ctx)
      when SliceExpr
        infer_slice(node, ctx)
      when FieldAccessExpr
        infer_field(node, ctx)
      when StructInitExpr
        infer_struct_init(node, ctx, expected)
      when EnumValueExpr
        infer_enum_value(node, ctx, expected)
      when IfExpr
        infer_if_expr(node, ctx)
      when OptionalElseExpr
        infer_optional_else(node, ctx)
      when ErrorUnwrapExpr
        infer_error_unwrap(node, ctx)
      when RangeExpr
        report(node, "range expression is only allowed in `for` loops and switch patterns", ctx && ctx.module_file)
        UNKNOWN
      when AsmExpr
        report(node, "asm requires an unsafe block", ctx && ctx.module_file) unless ctx.in_unsafe
        UNKNOWN
      when SizeofExpr
        infer_sizeof(node, ctx)
      when AlignofExpr
        infer_alignof(node, ctx)
      when OffsetofExpr
        infer_offsetof(node, ctx)
      else
        UNKNOWN
      end
    end

    def infer_var(node, ctx)
      name = node.name
      local = lookup_var(name, ctx)
      return local.type if local
      decl = @consts[name] || @statics[name] || @fns[name] || @structs[name] || @enums[name]
      if decl.nil?
        report(node, "undefined variable `#{name}`", ctx.module_file)
        return UNKNOWN
      end
      unless @consts.key?(name)
        if ctx.module_file != decl.module_file && !decl.exported
          report(node, "`#{name}` is private to its module", ctx.module_file)
        end
      end
      case decl
      when ConstDecl then @const_types[name] || UNKNOWN
      when StaticDecl then @statics_type[name] || UNKNOWN
      when EnumDecl
        NamedType.new(node.line, node.col, name: name, resolved: decl)
      when FnDecl then function_type_of(decl)
      else
        report(node, "`#{name}` is not a value", ctx.module_file)
        UNKNOWN
      end
    end

    def function_type_of(decl)
      FunctionType.new(0, 0, params: decl.params.map(&:type), ret: decl.return_type)
    end

    def infer_sizeof(node, ctx)
      t = resolve_type(node.type_node, ctx.module_file)
      return usize_type(node) if t == UNKNOWN
      node.value = @layout.size(t)
      usize_type(node)
    end

    def infer_alignof(node, ctx)
      t = resolve_type(node.type_node, ctx.module_file)
      return usize_type(node) if t == UNKNOWN
      node.value = @layout.align(t)
      usize_type(node)
    end

    def infer_offsetof(node, ctx)
      t = resolve_type(node.type_node, ctx.module_file)
      return usize_type(node) if t == UNKNOWN
      unless struct_type?(t)
        report(node, "offsetof requires a struct type, found #{type_name(t)}", ctx.module_file)
        return usize_type(node)
      end
      off = @layout.field_offset(t.resolved, node.field)
      if off.nil?
        report(node, "struct `#{t.name}` has no field `#{node.field}`", ctx.module_file)
        return usize_type(node)
      end
      node.value = off
      usize_type(node)
    end

    def infer_unary(node, ctx)
      case node.op
      when "-"
        t = infer_expr(node.operand, ctx)
        if numeric_type?(t) || t == UNKNOWN
          t
        else
          report(node, "unary `-` requires a numeric operand, found #{type_name(t)}", ctx.module_file)
          UNKNOWN
        end
      when "!"
        t = infer_expr(node.operand, ctx)
        if equal(t, bool_type) || t == UNKNOWN
          bool_type
        else
          report(node, "unary `!` requires a bool operand, found #{type_name(t)}", ctx.module_file)
          UNKNOWN
        end
      when "&"
        t = infer_expr(node.operand, ctx)
        if t.is_a?(FunctionType)
          t
        elsif t.nil?
          report(node, "cannot take the address of a void expression", ctx.module_file)
          UNKNOWN
        else
          PointerType.new(node.line, node.col, elem: t, const: false)
        end
      when "*"
        unless ctx.in_unsafe
          report(node, "dereferencing a raw pointer requires an unsafe block", ctx.module_file)
          return UNKNOWN
        end
        t = infer_expr(node.operand, ctx)
        if t.is_a?(PointerType)
          if void_type?(t.elem)
            report(node, "cannot dereference a void pointer", ctx.module_file)
            UNKNOWN
          else
            t.elem
          end
        elsif t == UNKNOWN
          UNKNOWN
        else
          report(node, "cannot dereference a value of type #{type_name(t)}", ctx.module_file)
          UNKNOWN
        end
      else
        UNKNOWN
      end
    end

    def infer_binary(node, ctx)
      a, b = infer_binary_operands(node, ctx)
      op = node.op
      case op
      when "&&", "||"
        if op == "||" && node.sugar && b != UNKNOWN && !equal(b, bool_type) && (base = chain_base(node.lhs))
          node.rhs = BinaryExpr.new(node.rhs.line, node.rhs.col, op: "==", lhs: base, rhs: node.rhs)
          b = infer_expr(node.rhs, ctx)
        end
        if (a == UNKNOWN || equal(a, bool_type)) && (b == UNKNOWN || equal(b, bool_type))
          bool_type
        else
          report(node, "operands of `#{op}` must be bool, found #{type_name(a)} and #{type_name(b)}", ctx.module_file)
          UNKNOWN
        end
      when "+", "-", "*", "/", "%"
        infer_arith(node, a, b, ctx)
      when "<<", ">>", "&", "|", "^"
        if (int_type?(a) || a == UNKNOWN) && (int_type?(b) || b == UNKNOWN)
          u = unify_numeric(node, a, b, node.lhs, node.rhs, ctx)
          u == UNKNOWN ? UNKNOWN : u
        else
          report(node, "operands of `#{op}` must be integers, found #{type_name(a)} and #{type_name(b)}", ctx.module_file)
          UNKNOWN
        end
      when "==", "!="
        if aggregate_compare?(a) || aggregate_compare?(b)
          if a == UNKNOWN || b == UNKNOWN
            bool_type
          else
            report(node, "cannot compare #{type_name(a)} and #{type_name(b)}", ctx.module_file)
            UNKNOWN
          end
        elsif pointer_or_null?(a, b, node) || optional_or_none?(a, b, node)
          bool_type
        elsif equal(a, b) || (numeric_type?(a) && numeric_type?(b) && unify_numeric(node, a, b, node.lhs, node.rhs, ctx) != UNKNOWN)
          bool_type
        elsif a == UNKNOWN || b == UNKNOWN
          bool_type
        else
          report(node, "cannot compare #{type_name(a)} and #{type_name(b)}", ctx.module_file)
          UNKNOWN
        end
      when "<", "<=", ">", ">="
        if numeric_type?(a) && numeric_type?(b)
          unify_numeric(node, a, b, node.lhs, node.rhs, ctx)
          bool_type
        elsif a == UNKNOWN || b == UNKNOWN
          bool_type
        else
          report(node, "operands of `#{op}` must be numeric, found #{type_name(a)} and #{type_name(b)}", ctx.module_file)
          UNKNOWN
        end
      else
        UNKNOWN
      end
    end

    def chain_base(node)
      case node
      when BinaryExpr
        if node.op == "||" && node.sugar
          chain_base(node.lhs)
        elsif node.op == "=="
          node.lhs
        end
      end
    end

    def infer_arith(node, a, b, ctx)
      if a.is_a?(PointerType) || b.is_a?(PointerType)
        return UNKNOWN if a == UNKNOWN || b == UNKNOWN
        unless ctx.in_unsafe
          report(node, "pointer arithmetic requires an unsafe block", ctx.module_file)
          return UNKNOWN
        end
        if node.op == "+" || node.op == "-"
          if a.is_a?(PointerType) && (int_type?(b) || b == UNKNOWN)
            return a
          elsif b.is_a?(PointerType) && (int_type?(a) || a == UNKNOWN)
            return b
          end
        end
        report(node, "invalid pointer arithmetic", ctx.module_file)
        return UNKNOWN
      end
      if numeric_type?(a) && numeric_type?(b)
        u = unify_numeric(node, a, b, node.lhs, node.rhs, ctx)
        return u == UNKNOWN ? UNKNOWN : u
      end
      return UNKNOWN if a == UNKNOWN || b == UNKNOWN
      report(node, "operands of `#{node.op}` must be numeric, found #{type_name(a)} and #{type_name(b)}", ctx.module_file)
      UNKNOWN
    end

    def pointer_or_null?(a, b, node)
      (ptr_like?(a) && node.rhs.is_a?(NullLiteral)) ||
        (ptr_like?(b) && node.lhs.is_a?(NullLiteral))
    end

    def ptr_like?(t)
      t.is_a?(PointerType) || t.is_a?(FunctionType)
    end

    def aggregate_compare?(t)
      case t
      when NamedType then struct_type?(t)
      when ArrayType, SliceType then true
      when OptionalType, ErrorType then aggregate_compare?(t.inner)
      else false
      end
    end

    def nullish?(node)
      node.is_a?(NullLiteral)
    end

    def noneish?(node)
      node.is_a?(NoneLiteral)
    end

    def infer_binary_operands(node, ctx)
      lhs = node.lhs
      rhs = node.rhs
      if nullish?(lhs) || noneish?(lhs)
        b = infer_expr(rhs, ctx)
        expected = if nullish?(lhs) && ptr_like?(b)
                     b
                   elsif noneish?(lhs) && b.is_a?(OptionalType)
                     b
                   end
        a = infer_expr(lhs, ctx, expected: expected)
        [a, b]
      elsif nullish?(rhs) || noneish?(rhs)
        a = infer_expr(lhs, ctx)
        expected = if nullish?(rhs) && ptr_like?(a)
                     a
                   elsif noneish?(rhs) && a.is_a?(OptionalType)
                     a
                   end
        b = infer_expr(rhs, ctx, expected: expected)
        [a, b]
      else
        [infer_expr(lhs, ctx), infer_expr(rhs, ctx)]
      end
    end

    def optional_or_none?(a, b, node)
      (a.is_a?(OptionalType) && node.rhs.is_a?(NoneLiteral)) ||
        (b.is_a?(OptionalType) && node.lhs.is_a?(NoneLiteral))
    end

    def infer_cast(node, ctx)
      src = infer_expr(node.expr, ctx)
      dst = resolve_type(node.type, ctx.module_file)
      return dst if src == UNKNOWN || dst == UNKNOWN
      if ctx.in_unsafe
        return dst if cast_supported?(src, dst)
        report(node, "unsupported cast from #{type_name(src)} to #{type_name(dst)}", ctx.module_file)
        return dst
      end
      if numeric_type?(src) && numeric_type?(dst)
        return dst
      end
      if src.is_a?(PointerType) && dst.is_a?(PointerType)
        if void_type?(dst.elem) && !void_type?(src.elem)
          return dst
        end
        if equal(src.elem, dst.elem)
          if (!src.const || dst.const) && (!src.volatile || dst.volatile)
            return dst
          end
        end
      end
      report(node, "cast from #{type_name(src)} to #{type_name(dst)} requires an unsafe block", ctx.module_file)
      dst
    end

    def cast_supported?(src, dst)
      return true if int_type?(src) && (int_type?(dst) || float_type?(dst))
      return true if float_type?(src) && (int_type?(dst) || float_type?(dst))
      return true if src.is_a?(PointerType) && (dst.is_a?(PointerType) || int_type?(dst))
      return true if int_type?(src) && dst.is_a?(PointerType)
      false
    end

    def infer_call(node, ctx)
      callee = node.callee
      if callee.is_a?(VarExpr)
        local = lookup_var(callee.name, ctx)
        if local
          if local.type.is_a?(FunctionType)
            return infer_indirect_call(node, local.type, ctx)
          end
          report(node, "`#{callee.name}` is a variable, not a function", ctx.module_file)
          return UNKNOWN
        end
        fn = @fns[callee.name]
        if fn.nil?
          if @consts.key?(callee.name) || @statics.key?(callee.name)
            report(node, "`#{callee.name}` is not a function", ctx.module_file)
          else
            report(node, "unknown function `#{callee.name}`", ctx.module_file)
          end
          return UNKNOWN
        end
        return infer_direct_call(node, fn, ctx)
      end
      ft = infer_expr(callee, ctx)
      if ft.is_a?(FunctionType)
        return infer_indirect_call(node, ft, ctx)
      end
      report(node, "cannot call a value of type #{type_name(ft)}", ctx.module_file)
      UNKNOWN
    end

    def infer_direct_call(node, fn, ctx)
      if ctx.module_file != fn.module_file && !fn.exported
        report(node, "cannot call `#{fn.name}`: it is private to its module", ctx.module_file)
        return UNKNOWN
      end
      report(node, "call to unsafe function `#{fn.name}` requires an unsafe block", ctx.module_file) if fn.unsafe && !ctx.in_unsafe
      if fn.variadic ? node.args.length < fn.params.length : node.args.length != fn.params.length
        expected = fn.variadic ? "at least #{fn.params.length}" : fn.params.length.to_s
        report(node, "function `#{fn.name}` expects #{expected} argument(s), got #{node.args.length}", ctx.module_file)
        return UNKNOWN
      end
      fn.params.zip(node.args).each do |param, arg|
        at = infer_expr(arg, ctx, expected: param.type)
        if at.nil?
          report(arg, "cannot pass a void value to parameter `#{param.name}`", ctx.module_file)
        elsif !compatible(at, param.type, arg, ctx)
          report(arg, "type mismatch for parameter `#{param.name}`: expected #{type_name(param.type)}, found #{type_name(at)}", ctx.module_file)
        end
      end
      if fn.variadic
        node.args[fn.params.length..].each do |arg|
          at = infer_expr(arg, ctx)
          report(arg, "cannot pass a void value to a variadic argument", ctx.module_file) if at.nil?
        end
      end
      fn.return_type
    end

    def infer_indirect_call(node, ft, ctx)
      node.callee.sema_type = ft if node.callee.is_a?(Expr)
      params = ft.params
      if node.args.length != params.length
        report(node, "function expects #{params.length} argument(s), got #{node.args.length}", ctx.module_file)
        return UNKNOWN
      end
      params.zip(node.args).each do |param, arg|
        at = infer_expr(arg, ctx, expected: param)
        if at.nil?
          report(arg, "cannot pass a void value to a function parameter", ctx.module_file)
        elsif !compatible(at, param, arg, ctx)
          report(arg, "type mismatch for parameter: expected #{type_name(param)}, found #{type_name(at)}", ctx.module_file)
        end
      end
      ft.ret
    end

    def infer_index(node, ctx)
      t = infer_expr(node.target, ctx)
      idx = infer_expr(node.index, ctx)
      unless int_type?(idx) || idx == UNKNOWN
        report(node.index, "array index must be an integer, found #{type_name(idx)}", ctx.module_file)
      end
      case t
      when ArrayType
        check_array_bounds(node, t.len_value, node.index, ctx) unless ctx.in_unsafe
        t.elem
      when SliceType
        t.elem
      when PointerType
        unless ctx.in_unsafe
          report(node, "pointer indexing requires an unsafe block", ctx.module_file)
          return UNKNOWN
        end
        if void_type?(t.elem)
          report(node, "cannot index a void pointer", ctx.module_file)
          return UNKNOWN
        end
        t.elem
      when UNKNOWN
        UNKNOWN
      else
        report(node, "cannot index a value of type #{type_name(t)}", ctx.module_file)
        UNKNOWN
      end
    end

    def infer_slice(node, ctx)
      t = infer_expr(node.target, ctx)
      [node.start, node.end_].compact.each do |bound|
        bt = infer_expr(bound, ctx)
        unless int_type?(bt) || bt == UNKNOWN
          report(bound, "slice bound must be an integer, found #{type_name(bt)}", ctx.module_file)
        end
      end
      case t
      when ArrayType
        unless ctx.in_unsafe
          check_array_bound(node, t.len_value, node.start, ctx) if node.start
          check_array_bound(node, t.len_value, node.end_, ctx) if node.end_
        end
        SliceType.new(node.line, node.col, elem: t.elem)
      when SliceType
        SliceType.new(node.line, node.col, elem: t.elem)
      when PointerType
        unless ctx.in_unsafe
          report(node, "slicing a pointer requires an unsafe block", ctx.module_file)
          return UNKNOWN
        end
        if void_type?(t.elem)
          report(node, "cannot slice a void pointer", ctx.module_file)
          return UNKNOWN
        end
        report(node, "cannot slice a volatile pointer", ctx.module_file) if t.volatile
        SliceType.new(node.line, node.col, elem: t.elem)
      when UNKNOWN
        UNKNOWN
      else
        report(node, "cannot slice a value of type #{type_name(t)}", ctx.module_file)
        UNKNOWN
      end
    end

    def check_array_bounds(node, len, index_node, ctx)
      return if len.nil?
      begin
        v = eval_const(index_node, ctx.module_file)
      rescue ConstError
        return
      end
      return unless v.is_a?(Integer)
      if v < 0 || v >= len
        report(index_node, "array index #{v} out of bounds (length #{len})", ctx.module_file)
      end
    end

    def check_array_bound(node, len, bound_node, ctx)
      return if len.nil?
      begin
        v = eval_const(bound_node, ctx.module_file)
      rescue ConstError
        return
      end
      return unless v.is_a?(Integer)
      if v < 0 || v > len
        report(bound_node, "slice bound #{v} out of bounds (length #{len})", ctx.module_file)
      end
    end

    def infer_field(node, ctx)
      t = infer_expr(node.target, ctx)
      field = node.field
      if t.is_a?(PointerType)
        inner = t.elem
        if struct_type?(inner)
          f = struct_field(inner.resolved, field)
          if f.nil?
            report(node, "struct `#{inner.name}` has no field `#{field}`", ctx.module_file)
            return UNKNOWN
          end
          return f.type
        end
        report(node, "cannot access field `#{field}` on pointer to #{type_name(inner)}", ctx.module_file)
        return UNKNOWN
      end
      case t
      when NamedType
        decl = t.resolved
        if decl.is_a?(StructDecl)
          f = struct_field(decl, field)
          if f.nil?
            report(node, "struct `#{t.name}` has no field `#{field}`", ctx.module_file)
            return UNKNOWN
          end
          f.type
        elsif decl.is_a?(EnumDecl)
          if enum_has_variant?(decl, field)
            t
          else
            report(node, "enum `#{t.name}` has no variant `#{field}`", ctx.module_file)
            UNKNOWN
          end
        else
          report(node, "cannot access field `#{field}` on type #{type_name(t)}", ctx.module_file)
          UNKNOWN
        end
      when SliceType
        case field
        when "len" then PrimitiveType.new(node.line, node.col, name: "usize")
        when "ptr" then PointerType.new(node.line, node.col, elem: t.elem, const: false)
        else
          report(node, "slice has no field `#{field}`", ctx.module_file)
          UNKNOWN
        end
      when OptionalType, ErrorType
        report(node, "cannot access field `#{field}` on #{type_name(t)}; unwrap it first", ctx.module_file)
        UNKNOWN
      when UNKNOWN
        UNKNOWN
      else
        report(node, "cannot access field `#{field}` on type #{type_name(t)}", ctx.module_file)
        UNKNOWN
      end
    end

    def infer_struct_init(node, ctx, expected)
      decl = @structs[node.type_name]
      if decl.nil?
        report(node, "unknown struct `#{node.type_name}`", ctx.module_file)
        return UNKNOWN
      end
      if ctx.module_file != decl.module_file && !decl.exported
        report(node, "struct `#{decl.name}` is private to its module", ctx.module_file)
      end
      used = {}
      node.fields.each do |f|
        if used[f.name]
          report(f, "duplicate field `#{f.name}` in struct initializer", ctx.module_file)
          next
        end
        used[f.name] = true
        fd = struct_field(decl, f.name)
        if fd.nil?
          report(f, "struct `#{decl.name}` has no field `#{f.name}`", ctx.module_file)
          next
        end
        if f.value.nil?
          local = lookup_var(f.name, ctx)
          if local.nil?
            report(f, "shorthand field `#{f.name}` requires a variable of that name", ctx.module_file)
          elsif !compatible(local.type, fd.type, VarExpr.new(f.line, f.col, name: f.name), ctx)
            report(f, "type mismatch for field `#{f.name}`: expected #{type_name(fd.type)}, found #{type_name(local.type)}", ctx.module_file)
          end
        else
          ft = infer_expr(f.value, ctx, expected: fd.type)
          next if ft.nil?
          unless compatible(ft, fd.type, f.value, ctx)
            report(f.value, "type mismatch for field `#{f.name}`: expected #{type_name(fd.type)}, found #{type_name(ft)}", ctx.module_file)
          end
        end
      end
      decl.fields.each do |fd|
        unless used[fd.name]
          report(node, "struct initializer for `#{decl.name}` is missing field `#{fd.name}`", ctx.module_file)
        end
      end
      NamedType.new(node.line, node.col, name: decl.name, resolved: decl)
    end

    def infer_enum_value(node, ctx, expected)
      if node.type_name
        decl = @enums[node.type_name]
        if decl.nil?
          report(node, "unknown enum `#{node.type_name}`", ctx.module_file)
          return UNKNOWN
        end
        if ctx.module_file != decl.module_file && !decl.exported
          report(node, "enum `#{decl.name}` is private to its module", ctx.module_file)
        end
        unless enum_has_variant?(decl, node.variant)
          report(node, "enum `#{decl.name}` has no variant `#{node.variant}`", ctx.module_file)
          return UNKNOWN
        end
        if expected && !enum_type?(expected)
          report(node, "type mismatch: expected #{type_name(expected)}, found enum value `#{node.variant}`", ctx.module_file)
        end
        return NamedType.new(node.line, node.col, name: decl.name, resolved: decl)
      end
      if expected && enum_type?(expected)
        decl = expected.resolved
        unless enum_has_variant?(decl, node.variant)
          report(node, "enum `#{decl.name}` has no variant `#{node.variant}`", ctx.module_file)
          return UNKNOWN
        end
        return expected
      end
      report(node, "cannot infer enum type of `.#{node.variant}`; annotate the type", ctx.module_file)
      UNKNOWN
    end

    def infer_if_expr(node, ctx)
      t = infer_expr(node.cond, ctx)
      unless equal(t, bool_type) || t == UNKNOWN
        report(node.cond, "if condition must be bool, found #{type_name(t)}", ctx.module_file)
      end
      if node.else_block.nil?
        report(node, "if expression requires an else branch", ctx.module_file)
        return UNKNOWN
      end
      t1 = block_value_type(node.then_block, ctx)
      t2 = block_value_type(node.else_block, ctx)
      return t1 == UNKNOWN ? t2 : t1 if t1 == UNKNOWN || t2 == UNKNOWN
      return t1 if equal(t1, t2)
      if numeric_type?(t1) && numeric_type?(t2)
        u = unify_numeric(node, t1, t2, last_expr(node.then_block), last_expr(node.else_block), ctx)
        return u == UNKNOWN ? UNKNOWN : u
      end
      report(node, "if branches have mismatched types: #{type_name(t1)} and #{type_name(t2)}", ctx.module_file)
      UNKNOWN
    end

    def block_value_type(block, ctx)
      check_block(block, ctx)
      last = block.stmts.last
      if last.is_a?(ExprStmt) && !last.terminated
        infer_expr(last.expr, ctx)
      else
        report(block, "if-expression branch must end with an expression (without `;`)", ctx.module_file)
        UNKNOWN
      end
    end

    def last_expr(block)
      last = block.stmts.last
      last.is_a?(ExprStmt) ? last.expr : nil
    end

    def infer_optional_else(node, ctx)
      t = infer_expr(node.target, ctx)
      inner = case t
              when OptionalType then t.inner
              when ErrorType then t.inner
              when UNKNOWN then return UNKNOWN
              else
                report(node, "`else` requires an optional or error value, found #{type_name(t)}", ctx.module_file)
                return UNKNOWN
              end
      check_block(node.else_block, ctx)
      last = node.else_block.stmts.last
      unless last.is_a?(ReturnStmt) || last.is_a?(BreakStmt) || last.is_a?(ContinueStmt)
        report(node, "else block of `maybe else` must diverge (return, break or continue)", ctx.module_file)
      end
      inner
    end

    def infer_error_unwrap(node, ctx)
      unless ctx.ret_type.is_a?(ErrorType)
        report(node, "`?` can only be used inside a function returning an error type (e.g. !T)", ctx.module_file)
        return UNKNOWN
      end
      t = infer_expr(node.target, ctx)
      if t.is_a?(ErrorType)
        t.inner
      elsif t == UNKNOWN
        UNKNOWN
      else
        report(node, "cannot unwrap a value of type #{type_name(t)} with `?`", ctx.module_file)
        UNKNOWN
      end
    end

    def infer_array_literal(node, ctx, expected)
      if node.repeat
        len = begin
          v = eval_const(node.repeat_count, ctx && ctx.module_file)
          if v.is_a?(Integer)
            report(node.repeat_count, "array length must be non-negative", ctx && ctx.module_file) if v < 0
            v
          else
            report(node.repeat_count, "array length must be an integer", ctx && ctx.module_file)
            nil
          end
        rescue ConstError => e
          report(node.repeat_count, "invalid array length: #{e.message}", ctx && ctx.module_file)
          nil
        end
        node.repeat_len = len
        et = infer_expr(node.elements[0], ctx, expected: expected.is_a?(ArrayType) ? expected.elem : nil)
        if expected.is_a?(ArrayType)
          if len != expected.len_value
            report(node, "array literal has #{len} element(s), expected #{expected.len_value}", ctx && ctx.module_file)
          end
          if et && !compatible(et, expected.elem, node.elements[0], ctx)
            report(node.elements[0], "type mismatch in array literal: expected #{type_name(expected.elem)}, found #{type_name(et)}", ctx && ctx.module_file)
          end
          return expected
        end
        return ArrayType.new(node.line, node.col, len_value: len, elem: et) if len
        return UNKNOWN
      end
      if expected.is_a?(ArrayType)
        if node.elements.length != expected.len_value
          report(node, "array literal has #{node.elements.length} element(s), expected #{expected.len_value}", ctx.module_file)
        end
        node.elements.each do |el|
          et = infer_expr(el, ctx, expected: expected.elem)
          next if et.nil?
          unless compatible(et, expected.elem, el, ctx)
            report(el, "type mismatch in array literal: expected #{type_name(expected.elem)}, found #{type_name(et)}", ctx.module_file)
          end
        end
        return expected
      end
      if node.elements.empty?
        report(node, "cannot infer element type of an empty array literal; annotate the type", ctx.module_file)
        return UNKNOWN
      end
      elem = infer_expr(node.elements[0], ctx)
      node.elements[1..].each do |el|
        et = infer_expr(el, ctx)
        next if et.nil?
        if equal(et, elem) || et == UNKNOWN
          next
        end
        if numeric_type?(elem) && numeric_type?(et)
          u = unify_numeric(node, elem, et, node.elements[0], el, ctx)
          elem = u unless u == UNKNOWN
        else
          report(el, "array literal elements have mismatched types", ctx.module_file)
        end
      end
      ArrayType.new(node.line, node.col, len_value: node.elements.length, elem: elem)
    end

    # scope helpers

    def lookup_var(name, ctx)
      ctx.scopes.reverse_each do |scope|
        return scope[name] if scope.key?(name)
      end
      nil
    end

    def define_var(name, type, mutable, ctx)
      ctx.scopes.last[name] = Local.new(type, mutable)
    end

    def usize_type(node)
      PrimitiveType.new(node.line, node.col, name: "usize")
    end

    def with_scope(ctx)
      ctx.scopes << {}
      yield
    ensure
      ctx.scopes.pop
    end

    def with_loop(ctx)
      ctx.loop_depth += 1
      yield
    ensure
      ctx.loop_depth -= 1
    end

    def with_unsafe(ctx)
      old = ctx.in_unsafe
      ctx.in_unsafe = true
      yield
    ensure
      ctx.in_unsafe = old
    end

    def report(node, message, file = nil)
      @reporter.report(file || node.module_file || "<input>", node.line, node.col, message)
    end

    public

    attr_reader :consts, :const_types, :const_values, :statics, :statics_type,
                :statics_value, :structs, :enums, :fns, :globals

    public :type_name, :equal, :int_type?, :float_type?, :numeric_type?,
           :struct_type?, :enum_type?, :void_type?, :signed?, :int_rank, :bool_type
  end
end
