module Amber::Router
  class RoutedResult(T)
    include Comparable(RoutedResult)

    getter params = {} of String => String

    def initialize(@terminal_segment : TerminalSegment(T)?)
    end

    delegate :[]?, :[], :[]=, to: @params

    def terminal_segment
      @terminal_segment.not_nil!
    end

    def path
      if found?
        terminal_segment.full_path
      else
        raise "Cannot provide route path when no route was found. Ask first with #found?"
      end
    end

    def found?
      !@terminal_segment.nil?
    end

    def payload?
      terminal_segment.route if found?
    end

    def payload
      payload?
    end

    def priority
      if found?
        terminal_segment.priority
      else
        -1
      end
    end

    def <=>(other : RoutedResult)
      priority <=> other.priority
    end

    def formatted_s(io : IO)
      io << "#<RoutedResult "

      if found?
        io << "found "
        io << terminal_segment.full_path
      else
        io << "not found"
      end
      io << '>'
    end
  end
end
