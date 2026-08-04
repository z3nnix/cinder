module Cinder
  module AST
    class Node
      attr_accessor :line, :col, :module_file

      def initialize(line, col, **fields)
        @line = line
        @col = col
        @module_file = nil
        fields.each { |k, v| instance_variable_set("@#{k}", v) }
      end
    end

    # Top-level 

    class Program < Node
      attr_accessor :decls, :uses, :path

      def initialize(line, col, decls:, uses:, path: nil)
        super(line, col, decls: decls, uses: uses, path: path)
      end
    end

    class UseStmt < Node
      attr_accessor :path, :module_ref
    end

    class Param < Node
      attr_accessor :name, :type
    end

    class StructField < Node
      attr_accessor :name, :type
    end

    class EnumVariant < Node
      attr_accessor :name
    end

    class FnDecl < Node
      attr_accessor :name, :params, :return_type, :body, :unsafe, :exported
      attr_accessor :inline, :naked, :section, :target, :extern, :variadic, :noreturn
    end

    class StructDecl < Node
      attr_accessor :name, :fields, :exported, :target
    end

    class EnumDecl < Node
      attr_accessor :name, :variants, :exported, :target
    end

    class ConstDecl < Node
      attr_accessor :name, :type, :value, :exported
    end

    class StaticDecl < Node
      attr_accessor :name, :type, :init, :exported, :section
    end

    # Types

    class TypeNode < Node; end

    class PrimitiveType < TypeNode
      attr_accessor :name
    end

    class ArrayType < TypeNode
      attr_accessor :len, :elem, :len_value
    end

    class SliceType < TypeNode
      attr_accessor :elem
    end

    class PointerType < TypeNode
      attr_accessor :elem, :const, :volatile
    end

    class OptionalType < TypeNode
      attr_accessor :inner
    end

    class ErrorType < TypeNode
      attr_accessor :inner
    end

    class NamedType < TypeNode
      attr_accessor :name, :resolved
    end

    class FunctionType < TypeNode
      attr_accessor :params, :ret
    end

    # Statements

    class Stmt < Node; end

    class Block < Stmt
      attr_accessor :stmts
    end

    class LetStmt < Stmt
      attr_accessor :name, :mutable, :type_annot, :init
    end

    class AssignStmt < Stmt
      attr_accessor :target, :op, :value
    end

    class IfStmt < Stmt
      attr_accessor :cond, :then_block, :elifs, :else_block
    end

    class WhileStmt < Stmt
      attr_accessor :cond, :body
    end

    class LoopStmt < Stmt
      attr_accessor :body
    end

    class ForRangeStmt < Stmt
      attr_accessor :var, :range, :body
    end

    class ForIterStmt < Stmt
      attr_accessor :index_var, :value_var, :iterable, :body
    end

    class SwitchCase < Node
      attr_accessor :pattern, :body
    end

    class SwitchStmt < Stmt
      attr_accessor :subject, :cases, :else_block
    end

    class ReturnStmt < Stmt
      attr_accessor :value
    end

    class BreakStmt < Stmt; end
    class ContinueStmt < Stmt; end

    class DeferStmt < Stmt
      attr_accessor :stmt
    end

    class StaticAssertStmt < Stmt
      attr_accessor :cond
    end

    class UnsafeBlock < Stmt
      attr_accessor :block
    end

    class AsmStmt < Stmt
      attr_accessor :asm_string, :inputs, :outputs
    end

    class ExprStmt < Stmt
      attr_accessor :expr, :terminated
    end

    # Expressions

    class Expr < Node
      attr_accessor :sema_type, :sema_expected
    end

    class IntLiteral < Expr
      attr_accessor :value, :suffix
    end

    class FloatLiteral < Expr
      attr_accessor :value, :suffix
    end

    class BoolLiteral < Expr
      attr_accessor :value
    end

    class CharLiteral < Expr
      attr_accessor :value
    end

    class StringLiteral < Expr
      attr_accessor :value, :kind
    end

    class NoneLiteral < Expr; end
    class NullLiteral < Expr; end

    class ArrayLiteralExpr < Expr
      attr_accessor :elements
      attr_accessor :repeat
      attr_accessor :repeat_count
      attr_accessor :repeat_len
    end

    class VarExpr < Expr
      attr_accessor :name
    end

    class BinaryExpr < Expr
      attr_accessor :op, :lhs, :rhs
    end

    class UnaryExpr < Expr
      attr_accessor :op, :operand
    end

    class CallExpr < Expr
      attr_accessor :callee, :args
    end

    class IndexExpr < Expr
      attr_accessor :target, :index
    end

    class SliceExpr < Expr
      attr_accessor :target, :start, :end_
    end

    class FieldAccessExpr < Expr
      attr_accessor :target, :field
    end

    class CastExpr < Expr
      attr_accessor :expr, :type
    end

    class StructInitField < Node
      attr_accessor :name, :value
    end

    class StructInitExpr < Expr
      attr_accessor :type_name, :fields
    end

    class EnumValueExpr < Expr
      attr_accessor :type_name, :variant
    end

    class IfExpr < Expr
      attr_accessor :cond, :then_block, :else_block
    end

    class OptionalElseExpr < Expr
      attr_accessor :target, :else_block
    end

    class ErrorUnwrapExpr < Expr
      attr_accessor :target
    end

    class RangeExpr < Expr
      attr_accessor :start, :end_, :inclusive
    end

    class AsmExpr < Expr
      attr_accessor :asm_string
    end

    class SizeofExpr < Expr
      attr_accessor :type_node, :value
    end

    class AlignofExpr < Expr
      attr_accessor :type_node, :value
    end

    class OffsetofExpr < Expr
      attr_accessor :type_node, :field, :value
    end

    # Dumper

    class Dumper
      def self.dump(node)
        new.dump_node(node)
      end

      def dump_node(n)
        case n
        when nil
          "nil"
        when Array
          n.map { |x| dump_node(x) }.join(" ")
        when String, Symbol
          n.inspect
        when Integer, Float, true, false
          n.to_s
        else
          fields = n.instance_variables.filter_map do |iv|
            v = n.instance_variable_get(iv)
            key = iv.to_s.delete_prefix("@")
            next if key == "line" || key == "col"
            next if v.nil? && %w[module_file section inline naked target volatile noreturn value].include?(key)
            "#{key}=#{dump_node(v)}"
          end
          "(#{n.class.name.split('::').last} #{fields.join(' ')})"
        end
      end
    end
  end
end
