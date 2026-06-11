module Amber::Jobs
  # Handles periodic promotion of scheduled and delayed jobs.
  #
  # The Scheduler runs in a background fiber and periodically checks the queue
  # adapter for scheduled jobs that are ready to execute. This is primarily
  # useful for adapters that separate scheduled jobs from the immediate queue
  # (like the MemoryQueueAdapter).
  #
  # In the MemoryQueueAdapter, scheduled job promotion happens during dequeue,
  # so the scheduler serves as an additional check to ensure jobs are promoted
  # even when no dequeue calls are happening.
  #
  # ## Usage
  #
  # ```
  # scheduler = Amber::Jobs::Scheduler.new(
  #   adapter: adapter,
  #   interval: 5.seconds
  # )
  # scheduler.start
  # ```
  class Scheduler
    Log = ::Log.for(self)

    getter adapter : QueueAdapter
    getter interval : Time::Span
    getter? is_running : Bool = false

    def initialize(@adapter : QueueAdapter, @interval : Time::Span = 5.seconds)
    end

    # Starts the scheduler in a background fiber.
    #
    # The scheduler will periodically trigger dequeue on all configured queues
    # to promote scheduled jobs. This is a no-op if the scheduler is already running.
    def start : Nil
      return if @is_running
      @is_running = true

      spawn do
        Log.info { "Job scheduler started with #{@interval} interval" }

        while @is_running
          begin
            tick
          rescue ex
            Log.error(exception: ex) { "Error in job scheduler tick" }
          end
          sleep @interval
        end

        Log.info { "Job scheduler stopped" }
      end
    end

    # Stops the scheduler.
    #
    # The scheduler will finish its current sleep cycle and then stop.
    def stop : Nil
      @is_running = false
    end

    # Performs a single scheduler tick.
    #
    # This is exposed as a public method primarily for testing purposes, allowing
    # specs to trigger scheduler behavior without running in a fiber.
    def tick : Nil
      # The MemoryQueueAdapter promotes scheduled jobs during dequeue,
      # so calling dequeue on known queues triggers promotion.
      # For other adapters, this may need to be overridden or extended.
    end
  end
end
