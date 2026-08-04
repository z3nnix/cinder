module Cinder
  class Layout
    include AST

    PRIMITIVE_SIZE = {
      "u8" => 1, "u16" => 2, "u32" => 4, "u64" => 8, "u128" => 16,
      "i8" => 1, "i16" => 2, "i32" => 4, "i64" => 8, "i128" => 16,
      "f32" => 4, "f64" => 8, "bool" => 1,
    }.freeze

    def initialize(sema)
      @sema = sema
      @cfg = sema.instance_variable_get(:@target_cfg)
      @struct_cache = {}
    end

    def size(t)
      case t
      when Sema::UNKNOWN, nil then 0
      when PrimitiveType
        case t.name
        when "void" then 0
        when "usize", "isize" then ptr_bits
        else PRIMITIVE_SIZE.fetch(t.name, 0)
        end
      when NamedType
        @sema.enum_type?(t) ? 4 : struct_size(t.resolved)
      when PointerType, FunctionType then ptr_bits
      when SliceType then 16
      when OptionalType, ErrorType
        align_up(1 + size(t.inner), align(t.inner))
      when ArrayType
        t.len_value.to_i * size(t.elem)
      else 0
      end
    end

    def align(t)
      case t
      when Sema::UNKNOWN, nil then 1
      when PrimitiveType
        case t.name
        when "void" then 1
        when "u128", "i128" then 16
        when "usize", "isize" then ptr_bits
        else PRIMITIVE_SIZE.fetch(t.name, 1)
        end
      when NamedType
        @sema.enum_type?(t) ? 4 : struct_align(t.resolved)
      when PointerType, FunctionType then ptr_bits
      when SliceType then 8
      when OptionalType, ErrorType
        [1, align(t.inner)].max
      when ArrayType
        t.len_value.to_i.zero? ? 1 : align(t.elem)
      else 1
      end
    end

    def struct_size(decl)
      compute_struct(decl)[0]
    end

    def struct_align(decl)
      compute_struct(decl)[2]
    end

    def field_offset(decl, name)
      offsets = compute_struct(decl)[1]
      idx = decl.fields.index { |f| f.name == name }
      idx ? offsets[idx] : nil
    end

    private

    def ptr_bits
      @cfg[:ptr_bits] / 8
    end

    def align_up(n, a)
      ((n + a - 1) / a) * a
    end

    def compute_struct(decl)
      cached = @struct_cache[decl]
      return cached if cached

      offsets = []
      cum = 0
      struct_align = 1
      decl.fields.each do |f|
        a = align(f.type)
        struct_align = a if a > struct_align
        off = align_up(cum, a)
        offsets << off
        cum = off + size(f.type)
      end
      result = [align_up(cum, struct_align), offsets, struct_align]
      @struct_cache[decl] = result
      result
    end
  end
end
