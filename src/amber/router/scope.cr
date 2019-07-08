module Amber
  module Router
    class Scope
      def initialize(@stack = [] of String)
      end

      def push(scope : String) : Array(String)
        @stack << scope
      end

      def pop : String
        @stack.pop
      end

      def to_s(io)
        io << @stack.join
      end
    end
  end
end
