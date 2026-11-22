module Amber::Mica::Core
  # How much work one operation (a parse, an XPath evaluation) may do.
  #
  # Work is counted in abstract *operations*: each format charges one
  # operation per byte it scans and per step of every loop that does not
  # advance through its input (hash probes, declaration lookups, tree walks).
  # The allowance grows with the operation's *units* (for a parser, the
  # bytes it has read plus any bytes it expanded; for a query, the nodes of
  # the document), so the budget enforces "work stays linear in the size of
  # the input" without capping legitimate large inputs:
  #
  #     allowance = min(base_operations + operations_per_unit * units, max_operations)
  #
  # *timeout* adds an optional wall-clock deadline measured from the start of
  # the operation (the meter's creation).
  #
  # ```
  # budget = Amber::Mica::Core::WorkBudget.new(operations_per_unit: 32, timeout: 2.seconds)
  # budget.allowance(1_000_i64) # => 1_032_000
  # ```
  struct WorkBudget
    # Operations allowed per unit of input.
    getter operations_per_unit : Int64
    # Operations allowed regardless of input size (covers fixed costs).
    getter base_operations : Int64
    # An absolute cap on operations, or nil for none.
    getter max_operations : Int64?
    # A wall-clock limit, or nil for none.
    getter timeout : Time::Span?

    def initialize(
      operations_per_unit : Int = 64,
      base_operations : Int = 1_000_000,
      max_operations : Int? = nil,
      @timeout : Time::Span? = nil,
    )
      raise ArgumentError.new("operations_per_unit must not be negative") if operations_per_unit < 0
      raise ArgumentError.new("base_operations must not be negative") if base_operations < 0
      if max_operations && max_operations < 0
        raise ArgumentError.new("max_operations must not be negative")
      end
      @operations_per_unit = operations_per_unit.to_i64
      @base_operations = base_operations.to_i64
      @max_operations = max_operations.try(&.to_i64)
    end

    # Returns a budget that never stops work (for trusted input and tests).
    def self.unlimited : self
      new(operations_per_unit: 0, base_operations: Int64::MAX)
    end

    # Returns the operations allowed after *units* units of input.
    def allowance(units : Int64) : Int64
      scaled = units > 0 && @operations_per_unit > 0 ? saturating_multiply(@operations_per_unit, units) : 0_i64
      total = Int64::MAX - @base_operations < scaled ? Int64::MAX : @base_operations + scaled
      if cap = @max_operations
        total = cap if cap < total
      end
      total
    end

    private def saturating_multiply(left : Int64, right : Int64) : Int64
      left > Int64::MAX // right ? Int64::MAX : left * right
    end
  end

  # Counts the work of one operation against a `WorkBudget`.
  #
  # Formats call `charge` on their hot paths: it adds and compares, and
  # returns true only when the meter needs a closer look, which the caller
  # gets from `enforce` (recomputing the allowance and, when a timeout is
  # set, reading the monotonic clock at most once every `CLOCK_INTERVAL`
  # operations). `enforce` raises a positioned `WorkBudgetExceededError` or
  # `DeadlineExceededError` when the budget or the deadline has run out.
  #
  # One meter can be shared by several operations (for example a parse and
  # the queries that follow it in one request), so they draw on one budget.
  #
  # WARNING: A meter is not concurrency-safe; use one per fiber.
  class WorkMeter
    # Operations between clock reads when a timeout is set.
    CLOCK_INTERVAL = 65_536_i64

    # The result of `verdict`.
    enum Verdict
      Within
      BudgetExceeded
      DeadlineExceeded
    end

    # Returns the budget this meter enforces.
    getter budget : WorkBudget

    # Returns the operations charged so far.
    getter operations : Int64 = 0_i64

    # Returns the units of input seen so far.
    getter units : Int64 = 0_i64

    @checkpoint : Int64
    # When the clock started; nil after a `restart` under a budget with no
    # timeout, which leaves the clock unread.
    @started : Time::Instant?

    def initialize(@budget : WorkBudget = WorkBudget.new)
      @started = Time.instant
      @checkpoint = 0_i64
      @checkpoint = next_checkpoint
    end

    # Starts the meter over under *budget*, as a new meter would: no
    # operations, no units, and the clock started now when *budget* has a
    # timeout. Lets a caller that runs many short operations reuse one
    # meter. Without a timeout the clock is not read (a clock read costs
    # more than a short operation), and `elapsed` is zero until the next
    # restart that has one.
    def restart(@budget : WorkBudget) : Nil
      @operations = 0_i64
      @units = 0_i64
      @started = @budget.timeout ? Time.instant : nil
      @checkpoint = 0_i64
      @checkpoint = next_checkpoint
    end

    # Adds *count* operations (saturating at `Int64::MAX`). Returns true
    # when the caller must call `enforce` or `verdict` (the budget may be
    # exhausted or the clock is due). Raises `ArgumentError` for a negative
    # count, so a miscalculated delta can never lower the recorded work.
    @[AlwaysInline]
    def charge(count : Int) : Bool
      raise_negative_charge(count) if count < 0
      @operations = count > Int64::MAX - @operations ? Int64::MAX : @operations + count
      @operations > @checkpoint
    end

    private def raise_negative_charge(count : Int) : NoReturn
      raise ArgumentError.new("Negative work charge: #{count}")
    end

    # Records *count* more units of input (saturating), which raises the
    # allowance. Raises `ArgumentError` for a negative count.
    @[AlwaysInline]
    def add_units(count : Int) : Nil
      raise ArgumentError.new("Negative unit count: #{count}") if count < 0
      @units = count > Int64::MAX - @units ? Int64::MAX : @units + count
    end

    # Checks the budget and the deadline (see `verdict`) and raises the
    # matching positioned error when either has run out:
    # `Amber::Mica::WorkBudgetExceededError` or `Amber::Mica::DeadlineExceededError`. The
    # block computes the position only when an error is raised. *context*
    # is appended to the message (for example the query being evaluated).
    #
    # ```
    # meter.enforce { Amber::Mica::Core::Position.new(offset) } if meter.charge(bytes)
    # ```
    def enforce(context : String? = nil, & : -> Position) : Nil
      verdict = self.verdict
      return if verdict.within?
      raise_exceeded(verdict, yield, context)
    end

    # Reads the clock now and raises `Amber::Mica::DeadlineExceededError` when the
    # timeout has passed. Formats call it at natural pauses: after each read
    # from an IO, and at the start and end of an operation.
    def enforce_deadline(context : String? = nil, & : -> Position) : Nil
      return unless deadline_passed?
      raise_exceeded(Verdict::DeadlineExceeded, yield, context)
    end

    # Raises the positioned error for a failing *verdict* (from `verdict`),
    # with *context* appended to the message. Callers that build an
    # expensive context string call `verdict` themselves and then this.
    def raise_exceeded(verdict : Verdict, position : Position, context : String? = nil) : NoReturn
      message = describe(verdict)
      # The context is clipped, so a long caller-supplied string cannot
      # grow the message.
      message = "#{message} #{Core.excerpt(context, Core::CONTEXT_CHARS)}" if context
      if verdict.deadline_exceeded?
        raise DeadlineExceededError.new(message, position, elapsed)
      end
      raise WorkBudgetExceededError.new(message, position, @operations, allowance) if verdict.budget_exceeded?
      raise ArgumentError.new("raise_exceeded needs a failing verdict")
    end

    # Returns how many more operations `charge` takes before it asks the
    # caller to check the meter (the next checkpoint: the allowance, or the
    # next clock read when a timeout is set). A caller that reads its input
    # in windows sizes each window by it, so the meter is checked before a
    # read it cannot pay for, not after.
    def headroom : Int64
      @checkpoint > @operations ? @checkpoint - @operations : 0_i64
    end

    # Returns the operations allowed for the units seen so far.
    def allowance : Int64
      @budget.allowance(@units)
    end

    # Returns the time since the meter started.
    def elapsed : Time::Span
      started = @started
      started ? Time.instant - started : Time::Span::ZERO
    end

    # Returns true when a timeout is set and has passed (reached counts:
    # a zero timeout has passed when the meter starts, whatever the clock
    # resolution). Reads the clock; formats call it at natural pauses
    # (after an IO refill).
    def deadline_passed? : Bool
      timeout = @budget.timeout
      return false unless timeout
      elapsed >= timeout
    end

    # Checks the budget and the deadline and moves the checkpoint.
    def verdict : Verdict
      return Verdict::BudgetExceeded if @operations > allowance
      if timeout = @budget.timeout
        return Verdict::DeadlineExceeded if elapsed >= timeout
      end
      @checkpoint = next_checkpoint
      Verdict::Within
    end

    # Returns a human-readable reason for a failing *verdict*.
    def describe(verdict : Verdict) : String
      case verdict
      in .budget_exceeded?
        "Work budget exhausted: #{@operations} operations for #{@units} units of input (allowance #{allowance})"
      in .deadline_exceeded?
        "Deadline exceeded: #{elapsed.total_milliseconds.round(1)} ms (timeout #{@budget.timeout.try(&.total_milliseconds)} ms)"
      in .within?
        "Within budget"
      end
    end

    private def next_checkpoint : Int64
      checkpoint = allowance
      if @budget.timeout
        clock = @operations &+ CLOCK_INTERVAL
        checkpoint = clock if clock < checkpoint
      end
      checkpoint
    end
  end
end
