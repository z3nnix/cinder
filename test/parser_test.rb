require "minitest/autorun"
require_relative "../lib/error_reporter"
require_relative "../lib/lexer"
require_relative "../lib/ast"
require_relative "../lib/parser"

class ParserTest < Minitest::Test
  include Cinder
  include Cinder::AST

  def parse(src)
    tokens = Lexer.new(src).tokenize
    Parser.new(tokens, "test").parse_program
  rescue DiagError => e
    raise e
  end

  def parse_ok(src)
    parse(src)
  end

  def assert_parse_error(src, pattern = nil)
    err = assert_raises(DiagError) { parse(src) }
    assert_match(pattern, err.message) if pattern
    err
  end

  def test_empty_program
    assert_equal [], parse_ok("").decls
  end

  def test_use
    prog = parse_ok('use "uart.cnd";')
    assert_equal 1, prog.uses.length
    assert_equal "uart.cnd", prog.uses[0].path
  end

  def test_fn_decl
    prog = parse_ok("fn foo() { }\nfn add(a: i32, b: i32) -> i32 { return a + b; }")
    fn = prog.decls[0]
    assert_instance_of FnDecl, fn
    assert_equal "foo", fn.name
    assert_nil fn.return_type
    add = prog.decls[1]
    assert_equal "i32", add.return_type.name
    assert_equal %w[a b], add.params.map(&:name)
  end

  def test_fn_attrs
    prog = parse_ok(<<~CND)
      fn inline add_small(a: u8, b: u8) -> u8 inline { a + b }
      fn naked irq_handler() naked { unsafe { asm("push {r0-r12}"); } }
      fn boot_entry() section(".boot") { }
      unsafe fn dangerous() { }
    CND
    assert prog.decls[0].inline
    assert prog.decls[1].naked
    assert_equal ".boot", prog.decls[2].section
    assert prog.decls[3].unsafe
  end

  def test_export
    prog = parse_ok("export fn uart_init(base: usize, baud: u32) -> Uart { }\nexport struct Uart { base: usize; baud: u32; }")
    assert prog.decls[0].exported
    assert prog.decls[1].exported
    assert_equal %w[base baud], prog.decls[1].fields.map(&:name)
  end

  def test_target_attr
    prog = parse_ok('#[target("arm")] fn arm_specific() { }')
    assert_equal "arm", prog.decls[0].target
  end

  def test_const_static
    prog = parse_ok("const MAX_SIZE = 4096;\nconst TIMEOUT_MS: u32 = 1000;\nstatic GLOBAL_COUNTER: u32 = 0;")
    assert_equal 4096, prog.decls[0].value.value
    assert_equal "u32", prog.decls[1].type.name
    assert_equal "GLOBAL_COUNTER", prog.decls[2].name
  end

  def test_static_section
    prog = parse_ok('static mb_header: [3]u32 = [0x1BADB002, 0, 0xE4524FFE] section(".multiboot");')
    static = prog.decls[0]
    assert_equal "mb_header", static.name
    assert_equal ".multiboot", static.section
    assert_instance_of ArrayType, static.type
  end

  def test_fn_noreturn
    prog = parse_ok("fn panic() noreturn { loop { } }\nfn normal() { }")
    assert prog.decls[0].noreturn
    refute prog.decls[1].noreturn
  end

  def test_enum
    prog = parse_ok("enum Color { Red; Green; Blue; }")
    assert_equal %w[Red Green Blue], prog.decls[0].variants.map(&:name)
  end

  def test_types
    prog = parse_ok(<<~CND)
      fn f1(a: [4]u8, b: []u8) { }
      fn f2(p: *u32, q: *const u32) { }
      fn f3(a: ?u32, b: !u16) { }
      fn f4(s: StructName) { }
    CND
    assert_instance_of ArrayType, prog.decls[0].params[0].type
    assert_instance_of SliceType, prog.decls[0].params[1].type
    assert_instance_of PointerType, prog.decls[1].params[0].type
    assert prog.decls[1].params[1].type.const
    assert_instance_of OptionalType, prog.decls[2].params[0].type
    assert_instance_of ErrorType, prog.decls[2].params[1].type
    assert_instance_of NamedType, prog.decls[3].params[0].type
  end

  def test_volatile_pointer_types
    prog = parse_ok(<<~CND)
      fn f1(v: *volatile u32) { }
      fn f2(c: *const volatile u32) { }
      fn f3(r: *volatile const u32) { }
    CND
    t1 = prog.decls[0].params[0].type
    assert_instance_of PointerType, t1
    refute t1.const
    assert t1.volatile
    assert_equal "u32", t1.elem.name
    t2 = prog.decls[1].params[0].type
    assert t2.const
    assert t2.volatile
    t3 = prog.decls[2].params[0].type
    assert t3.const
    assert t3.volatile
  end

  def test_array_len_from_const
    prog = parse_ok("fn f(a: [VGA_WIDTH]u8) { }")
    assert_instance_of VarExpr, prog.decls[0].params[0].type.len
  end

  def test_let
    prog = parse_ok("fn f() { let x = 42; let mut y: u32 = 100; }")
    lets = prog.decls[0].body.stmts
    assert_instance_of LetStmt, lets[0]
    assert_equal "x", lets[0].name
    refute lets[0].mutable
    assert lets[1].mutable
    assert_equal "u32", lets[1].type_annot.name
  end

  def test_let_missing_init
    assert_parse_error("fn f() { let z: u32; }", /must be initialized/)
  end

  def test_array_repeat_literal
    prog = parse_ok("fn f() { let a = [0; 4]; let b = [1, 2]; let c: [8]u8 = [0; 8]; }")
    lets = prog.decls[0].body.stmts
    a = lets[0].init
    assert_instance_of ArrayLiteralExpr, a
    assert a.repeat
    assert_instance_of IntLiteral, a.repeat_count
    assert_equal 1, a.elements.length
    b = lets[1].init
    refute b.repeat
    assert_equal 2, b.elements.length
    c = lets[2].init
    assert c.repeat
  end

  def test_array_repeat_bad_forms
    assert_parse_error("fn f() { let a = [1, 2; 3]; }", /expected `,` or `]`/)
    assert_parse_error("fn f() { let a = [0; 4, 5]; }", /expected `]` in array literal/)
    assert_parse_error("fn f() { let a = [; 4]; }", /unexpected token/)
  end

  def test_assign
    prog = parse_ok("fn f() { x = 1; counter += 1; *ptr = 42; obj.field = 5; data[i] = 7; }")
    assigns = prog.decls[0].body.stmts
    assert_instance_of AssignStmt, assigns[0]
    assert_equal "=", assigns[0].op
    assert_equal "+=", assigns[1].op
    assert_instance_of UnaryExpr, assigns[2].target
    assert_instance_of FieldAccessExpr, assigns[3].target
    assert_instance_of IndexExpr, assigns[4].target
  end

  def test_if_stmt
    prog = parse_ok(<<~CND)
      fn f(x: i32) {
        if x > 10 { a(); } else if x > 5 { b(); } else { c(); }
      }
    CND
    ifs = prog.decls[0].body.stmts[0]
    assert_instance_of IfStmt, ifs
    assert_equal 1, ifs.elifs.length
    refute_nil ifs.else_block
  end

  def test_if_expr
    prog = parse_ok("fn f(a: i32, b: i32) -> i32 { let max = if a > b { a } else { b }; return max; }")
    stmts = prog.decls[0].body.stmts
    init = stmts[0].init
    assert_instance_of IfExpr, init
  end

  def test_loops
    prog = parse_ok(<<~CND)
      fn f() {
        loop { break; }
        let mut i = 0;
        while i < 10 { i += 1; }
        for i in 0..10 { work(i); }
        for i in 0..=5 { work(i); }
        for value in arr { log(value); }
        for i, value in arr { log(i, value); }
        if i > 5 { continue; }
      }
    CND
    stmts = prog.decls[0].body.stmts
    assert_instance_of LoopStmt, stmts[0]
    assert_instance_of WhileStmt, stmts[2]
    range = stmts[3]
    assert_instance_of ForRangeStmt, range
    assert_equal 0, range.range.start.value
    assert_equal 10, range.range.end_.value
    refute range.range.inclusive
    assert stmts[4].range.inclusive
    assert_instance_of ForIterStmt, stmts[5]
    assert_nil stmts[5].index_var
    assert_instance_of ForIterStmt, stmts[6]
    assert_equal "i", stmts[6].index_var
  end

  def test_switch
    prog = parse_ok(<<~CND)
      fn f(value: i32) {
        switch value {
          0 => log("zero");
          1..10 => log("small");
          42 => log("answer");
          else => log("other");
        }
      }
    CND
    sw = prog.decls[0].body.stmts[0]
    assert_instance_of SwitchStmt, sw
    assert_equal 3, sw.cases.length
    assert_instance_of IntLiteral, sw.cases[0].pattern
    assert_instance_of RangeExpr, sw.cases[1].pattern
    refute_nil sw.else_block
  end

  def test_switch_enum
    prog = parse_ok(<<~CND)
      fn f(c: Color) {
        switch c {
          Color.Red => log("red");
          .Green => log("green");
        }
      }
    CND
    sw = prog.decls[0].body.stmts[0]
    assert_instance_of FieldAccessExpr, sw.cases[0].pattern
    assert_instance_of EnumValueExpr, sw.cases[1].pattern
  end

  def test_defer
    prog = parse_ok("fn f() { let ptr = alloc(1024); defer free(ptr); }")
    stmts = prog.decls[0].body.stmts
    assert_instance_of DeferStmt, stmts[1]
    assert_instance_of ExprStmt, stmts[1].stmt
  end

  def test_defer_if
    prog = parse_ok("fn f() { let ptr = alloc(1024); defer if ptr != null { free(ptr); }; }")
    stmts = prog.decls[0].body.stmts
    assert_instance_of DeferStmt, stmts[1]
    assert_instance_of IfStmt, stmts[1].stmt
  end

  def test_unsafe_block
    prog = parse_ok(<<~CND)
      fn f() {
        unsafe {
          let reg = 0x40001000 as *u32;
          *reg = 0xDEADBEEF;
          asm("wfi");
        }
      }
    CND
    block = prog.decls[0].body.stmts[0]
    assert_instance_of UnsafeBlock, block
    assert_instance_of AsmExpr, block.block.stmts[2].expr
  end

  def test_optional_else
    prog = parse_ok("fn f() { let val = maybe else { return 0; }; return val; }")
    stmts = prog.decls[0].body.stmts
    assert_instance_of OptionalElseExpr, stmts[0].init
  end

  def test_error_unwrap
    prog = parse_ok("fn f() { let val = read_sensor()?; return val as u32 + 100; }")
    stmts = prog.decls[0].body.stmts
    assert_instance_of ErrorUnwrapExpr, stmts[0].init
    cast = stmts[1].value
    assert_instance_of BinaryExpr, cast
    assert_instance_of CastExpr, cast.lhs
  end

  def test_struct_init
    prog = parse_ok(<<~CND)
      fn f() {
        let uart = Uart { base, baud };
        let gpio = GPIO { base: 0x40020000, pin: 13, mode: .Output };
        let ch = VgaChar { ch: ' ', color: buf.color };
      }
    CND
    inits = prog.decls[0].body.stmts.map(&:init)
    assert_instance_of StructInitExpr, inits[0]
    assert_nil inits[0].fields[0].value
    assert_instance_of EnumValueExpr, inits[1].fields[2].value
    assert_instance_of FieldAccessExpr, inits[2].fields[1].value
  end

  def test_slices
    prog = parse_ok(<<~CND)
      fn f(arr: [4]u8) {
        let a = arr[0..2];
        let b = arr[1..];
        let c = arr[..3];
        let d = arr[..];
        let e = arr[0];
      }
    CND
    stmts = prog.decls[0].body.stmts
    assert_instance_of SliceExpr, stmts[0].init
    assert_nil stmts[1].init.end_
    assert_nil stmts[2].init.start
    assert_nil stmts[3].init.start
    assert_nil stmts[3].init.end_
    assert_instance_of IndexExpr, stmts[4].init
  end

  def test_strings_and_chars
    prog = parse_ok("fn f() { let m = \"Hello\"; let c = 'A'; let r = r\"C:x\"; let d = b\"raw\"; let s = c\"Hi\\0\"; }")
    inits = prog.decls[0].body.stmts.map(&:init)
    assert_instance_of StringLiteral, inits[0]
    assert_equal :normal, inits[0].kind
    assert_instance_of CharLiteral, inits[1]
    assert_instance_of StringLiteral, inits[2]
    assert_equal :raw, inits[2].kind
    assert_equal :byte, inits[3].kind
    assert_equal :cstring, inits[4].kind
  end

  def test_cast_precedence
    prog = parse_ok("fn f(val: u32) -> u32 { return val as u32 + 100; }")
    ret = prog.decls[0].body.stmts[0]
    assert_instance_of BinaryExpr, ret.value
    assert_equal "+", ret.value.op
    assert_instance_of CastExpr, ret.value.lhs
  end

  def test_bitwise_binary
    prog = parse_ok("fn f(op: u16) -> u8 { return ((op >> 8) & 0xF) as u8 | 0x01; }")
    ret = prog.decls[0].body.stmts[0]
    root = ret.value
    assert_instance_of BinaryExpr, root
    assert_equal "|", root.op
    assert_instance_of CastExpr, root.lhs
    inner = root.lhs.expr
    assert_instance_of BinaryExpr, inner
    assert_equal "&", inner.op
    assert_equal 0xF, inner.rhs.value
  end

  def test_bitwise_xor_shift
    prog = parse_ok("fn f(a: u8, b: u8) -> u8 { return a ^ b; }")
    ret = prog.decls[0].body.stmts[0]
    assert_instance_of BinaryExpr, ret.value
    assert_equal "^", ret.value.op
  end

  def test_missing_semicolon
    assert_parse_error("fn f() { let x = 10 }", /expected `;`/)
  end

  def test_unbalanced_brace
    assert_parse_error("fn f() { ", /unterminated block/)
  end

  def test_bad_top_level
    assert_parse_error("let x = 10;", /top level/)
  end

  def test_shadowing_ok
    parse_ok("fn f() { let x = 10; let x = x + 5; }")
  end

  def test_implicit_return_last_expr
    prog = parse_ok("fn mul(a: i32, b: i32) -> i32 { a * b }")
    stmts = prog.decls[0].body.stmts
    assert_equal 1, stmts.length
    assert_instance_of ExprStmt, stmts[0]
  end

  # ---------- function pointers ----------

  def test_fn_type_annotation
    prog = parse_ok("fn apply(f: fn(i32, i32) -> i32) -> i32 { return f(1, 2); }")
    param = prog.decls[0].params[0]
    assert_instance_of FunctionType, param.type
    assert_equal 2, param.type.params.length
    assert_equal "i32", param.type.ret.name
  end

  def test_fn_type_void_return
    prog = parse_ok("fn run(cb: fn()) { cb(); }")
    param = prog.decls[0].params[0]
    assert_instance_of FunctionType, param.type
    assert_nil param.type.ret
  end

  def test_fn_type_nested_param
    prog = parse_ok("fn h(g: fn(fn() -> i32) -> i32) -> i32 { return 0; }")
    param = prog.decls[0].params[0].type
    assert_instance_of FunctionType, param
    assert_instance_of FunctionType, param.params[0]
  end

  def test_fn_ptr_extern_param
    prog = parse_ok("extern fn atexit(cb: fn() -> void) -> i32;")
    t = prog.decls[0].params[0].type
    assert_instance_of FunctionType, t
    assert_equal 0, t.params.length
    assert_equal "void", t.ret.name
  end

  # ---------- sizeof / alignof / offsetof ----------

  def test_sizeof_expr
    prog = parse_ok("fn main() { let s: usize = sizeof(i32); }")
    init = prog.decls[0].body.stmts[0].init
    assert_instance_of SizeofExpr, init
  end

  def test_sizeof_struct_type
    prog = parse_ok("struct P { a: i32; } fn main() { let s: usize = sizeof(struct P); }")
    init = prog.decls[1].body.stmts[0].init
    assert_instance_of SizeofExpr, init
    assert_equal "P", init.type_node.name
  end

  def test_alignof_expr
    prog = parse_ok("fn main() { let s: usize = alignof(i64); }")
    init = prog.decls[0].body.stmts[0].init
    assert_instance_of AlignofExpr, init
    assert_equal "i64", init.type_node.name
  end

  def test_offsetof_expr
    prog = parse_ok("struct P { a: i32; b: u8; } fn main() { let o: usize = offsetof(struct P, b); }")
    init = prog.decls[1].body.stmts[0].init
    assert_instance_of OffsetofExpr, init
    assert_equal "b", init.field
  end

  # ---------- static_assert ----------

  def test_static_assert_top_level
    prog = parse_ok("static_assert(sizeof(i32) == 4);\nfn main() { }")
    assert_instance_of StaticAssertStmt, prog.decls[0]
  end

  def test_static_assert_in_body
    prog = parse_ok("fn main() { static_assert(1 == 1); }")
    stmt = prog.decls[0].body.stmts[0]
    assert_instance_of StaticAssertStmt, stmt
    assert_instance_of BinaryExpr, stmt.cond
  end

  def test_static_assert_missing_paren
    assert_parse_error("static_assert 1 == 1;\nfn main() { }", /expected `\(`/)
  end
end
