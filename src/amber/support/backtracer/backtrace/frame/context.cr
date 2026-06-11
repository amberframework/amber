module Backtracer
  struct Backtrace::Frame::Context
    # The line number this `Context` refers to.
    getter lineno : Int32

    # An array of lines before `lineno`.
    getter pre : Array(String)

    # The line at `lineno`.
    getter line : String

    # An array of lines after `lineno`.
    getter post : Array(String)

    def initialize(@lineno, @pre, @line, @post)
    end

    # Returns an array composed of context lines from `pre`,
    # `line` and `post`.
    def to_a : Array(String)
      ([] of String).tap do |ary|
        ary.concat(pre)
        ary << line
        ary.concat(post)
      end
    end

    # Returns hash with context lines, where line numbers are
    # the keys and the lines itself are the values.
    def to_h : Hash(Int32, String)
      ({} of Int32 => String).tap do |hash|
        base_index = lineno - pre.size
        pre.each_with_index do |code, index|
          hash[base_index + index] = code
        end

        hash[lineno] = line

        base_index = lineno + 1
        post.each_with_index do |code, index|
          hash[base_index + index] = code
        end
      end
    end
  end
end
