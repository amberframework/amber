module Amber::Mica
  # Base class of the errors Mica raises for its own failures, in every
  # format: parse, limit, budget, deadline, encoding, query, edit and
  # builder failures. Rescue `Amber::Mica::Error` to handle all of them. Lookups by
  # key follow Crystal's `Hash#[]` instead: `[]` raises `KeyError` for a
  # missing attribute and `[]?` returns nil.
  class Error < Exception
  end

  # Raised when input does not follow its format's grammar.
  #
  # `position` says where: the 0-based byte offset in the original input,
  # and for text formats the 1-based line and column (the column counts
  # characters). Formats without lines (binary formats) report line and
  # column 0.
  class ParseError < Error
    # Where the error was detected.
    getter position : Core::Position

    # The message without the position suffix.
    getter detail : String

    def initialize(@detail : String, @position : Core::Position)
      super("#{@detail} (#{@position})")
    end

    # Returns the 1-based line, or 0 for formats without lines.
    def line_number : Int32
      @position.line
    end

    # Returns the 1-based column in characters, or 0 for formats without
    # lines.
    def column_number : Int32
      @position.column
    end

    # Returns the 0-based byte offset in the original input.
    def byte_offset : Int64
      @position.byte_offset
    end
  end

  # Raised when the input's bytes are not valid in its encoding, or when it
  # uses an encoding the format does not accept.
  class EncodingError < ParseError
  end

  # Raised when a configured safety limit (size, depth, count, expansion,
  # work budget or deadline) is exceeded.
  class LimitExceededError < ParseError
  end

  # Raised when an operation needs more work than its `Core::WorkBudget`
  # allows. *operations* is the work done when the meter stopped it and
  # *allowance* what the budget allowed at that point.
  class WorkBudgetExceededError < LimitExceededError
    getter operations : Int64
    getter allowance : Int64

    def initialize(detail : String, position : Core::Position, @operations : Int64, @allowance : Int64)
      super(detail, position)
    end
  end

  # Raised when an operation runs past the wall-clock timeout of its
  # `Core::WorkBudget`.
  class DeadlineExceededError < LimitExceededError
    getter elapsed : Time::Span

    def initialize(detail : String, position : Core::Position, @elapsed : Time::Span)
      super(detail, position)
    end
  end
end
