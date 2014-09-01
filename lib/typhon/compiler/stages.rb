require 'pp'
require 'typhon/parser'
require 'typhon/ast'

module Typhon

  class Generator < Rubinius::ToolSets::Runtime::Generator
    def push_typhon_env
      push_cpath_top
      find_const :Typhon
      find_const :Environment
    end

    def py_send(name, arity)
      send name, arity
    end
  end

  class Stage


    # This stage takes a tree of Typhon::AST nodes and
    # simply calls the bytecode method on them.
    class Generator < Rubinius::ToolSets::Runtime::Compiler::Stage
      next_stage Rubinius::ToolSets::Runtime::Compiler::Encoder
      attr_accessor :variable_scope, :root

      def initialize(compiler, last)
        super
        @compiler = compiler
        @variable_scope = nil
        compiler.generator = self
      end

      def run
        root = @root.new @input
        root.file = @compiler.parser.filename

        @output = Typhon::Generator.new
        root.variable_scope = @variable_scope
        root.bytecode @output

        @output.close
        run_next
      end

    end

    # AST trasnformation for evaling source string.
    #
    # This stage removes the ModuleNode from root of AST tree if
    # the code being compiled is going to be used for eval. We remove
    # the module, because in eval we must not return the module object
    # Also if the last statement is a DiscardNode, we replace it with
    # its inner expression, in order to return a value.
    #
    # If the source is not being compiled for eval, then output is
    # the same AST given as input.
    class EvalExpr < Rubinius::ToolSets::Runtime::Compiler::Stage
      next_stage Generator

      def initialize(compiler, last)
        @compiler = compiler
        super
      end

      def run
        @output = @input
        if @compiler.generator.root == Rubinius::ToolSets::Runtime::AST::EvalExpression
          @output = @output.node # drop top module node, only use stmt
          if @output.nodes.last.kind_of?(AST::DiscardNode)
            @output.nodes[-1] = @output.nodes.last.expr
          end
        end
        run_next
      end
    end

    # This stage takes a ruby array as produced by bin/astpretty.py
    # and produces a tree of Typhon::AST nodes.
    class PyAST < Rubinius::ToolSets::Runtime::Compiler::Stage
      next_stage EvalExpr

      def initialize(compiler, last)
        @compiler = compiler
        super
      end

      def run
        @output = Typhon::AST.from_sexp(@input)
        pp(@output) if @compiler.parser.print.ast?
        run_next
      end
    end

    # This stage takes python code and produces a ruby array
    # containing representation of the python source.
    # We are currently using python's own parser, so we just
    # read the sexp as its printed by bin/astpretty.py
    class PyCode < Rubinius::ToolSets::Runtime::Compiler::Stage

      stage :typhon_code
      next_stage PyAST
      attr_reader :filename, :line
      attr_accessor :print

      def initialize(compiler, last)
        super
        @print = Compiler::Print.new
        compiler.parser = self
      end

      def input(code, filename = "eval", line = 1)
        @code = code
        @filename = filename
        @line = line
      end

      def run
        @output = Parser.new.parse(@code)
        pp(@output) if @print.sexp?
        run_next
      end
    end

    # This stage takes a python filename and produces a ruby array
    # containing representation of the python source.
    # We are currently using python's own parser, so we just
    # read the sexp as its printed by bin/astpretty.py
    class PyFile < Rubinius::ToolSets::Runtime::Compiler::Stage

      stage :typhon_file
      next_stage PyAST
      attr_reader :filename, :line
      attr_accessor :print

      def initialize(compiler, last)
        super
        @print = Compiler::Print.new
        compiler.parser = self
      end

      def input(filename, line = 1)
        @filename = filename
        @line = line
      end

      def run
        @output = Parser.new.parse(File.read(@filename))
        pp(@output) if @print.sexp?
        run_next
      end
    end

  end
end
