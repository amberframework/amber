require "./queue_adapter"
require "./job_envelope"

module Amber::Jobs
  # Executes background jobs by polling the queue adapter.
  #
  # A Worker runs in a background fiber, repeatedly checking configured queues
  # for available jobs. When a job is found, it deserializes and executes it,
  # handling retries and dead job marking on failure.
  #
  # ## Usage
  #
  # ```
  # worker = Amber::Jobs::Worker.new(
  #   adapter: Amber::Jobs.adapter,
  #   list_of_queues: ["default", "critical"],
  #   polling_interval: 1.second
  # )
  # worker.start
  # ```
  #
  # ## Work Stealing
  #
  # When `idle_only` is set to true, the worker will only process jobs when
  # there are no pending HTTP requests. This allows idle web server instances
  # to contribute to job processing without impacting request latency.
  class Worker
    Log = ::Log.for(self)

    getter adapter : QueueAdapter
    getter list_of_queues : Array(String)
    getter polling_interval : Time::Span
    getter? is_running : Bool = false
    getter? idle_only : Bool = false
    getter jobs_processed : Int64 = 0_i64

    # Tracks pending HTTP request count for work-stealing mode.
    # This is incremented/decremented by the HTTP server middleware.
    class_property pending_request_count : Int64 = 0_i64
    class_property pending_request_mutex : Mutex = Mutex.new

    def initialize(
      @adapter : QueueAdapter,
      @list_of_queues : Array(String) = ["default"],
      @polling_interval : Time::Span = 1.second,
      @idle_only : Bool = false,
    )
    end

    # Starts the worker in a background fiber.
    #
    # The worker will poll all configured queues in order, executing any
    # available jobs. This is a no-op if the worker is already running.
    def start : Nil
      return if @is_running
      @is_running = true

      spawn do
        Log.info { "Job worker started for queues: #{@list_of_queues.join(", ")}" }

        while @is_running
          begin
            process_next_job
          rescue ex
            Log.error(exception: ex) { "Unexpected error in job worker loop" }
          end
          sleep @polling_interval
        end

        Log.info { "Job worker stopped" }
      end
    end

    # Stops the worker.
    #
    # The worker will finish processing its current job (if any), complete
    # its current sleep cycle, and then stop.
    def stop : Nil
      @is_running = false
    end

    # Attempts to dequeue and execute a single job from the configured queues.
    #
    # This method is exposed publicly for testing purposes.
    def process_next_job : Bool
      return false if @idle_only && !is_server_idle?

      @list_of_queues.each do |queue_name|
        if envelope = @adapter.dequeue(queue_name)
          execute(envelope)
          return true
        end
      end

      false
    end

    # Executes a single job envelope.
    #
    # Deserializes the job, runs it, and handles success/failure/retry logic.
    private def execute(envelope : JobEnvelope) : Nil
      envelope.mark_as_running

      begin
        job = Amber::Jobs.deserialize(envelope.job_class, envelope.payload)

        unless job
          error_message = "Unable to deserialize job class: #{envelope.job_class}"
          Log.error { error_message }
          @adapter.mark_dead(envelope.id, error_message) if @adapter.responds_to?(:mark_dead)
          @adapter.mark_failed(envelope.id, error_message)
          return
        end

        job.perform
        envelope.mark_as_completed
        @adapter.mark_completed(envelope.id)
        @jobs_processed += 1

        Log.debug { "Job #{envelope.id} (#{envelope.job_class}) completed successfully" }
      rescue ex
        handle_failure(envelope, ex)
      end
    end

    # Handles a job execution failure.
    #
    # If the job has not exceeded its max retries, it is re-enqueued with
    # exponential backoff. Otherwise, it is marked as dead.
    private def handle_failure(envelope : JobEnvelope, exception : Exception) : Nil
      error_message = "#{exception.class}: #{exception.message}"

      Log.warn { "Job #{envelope.id} (#{envelope.job_class}) failed (attempt #{envelope.attempts}/#{envelope.max_retries}): #{error_message}" }

      if envelope.has_exceeded_max_retries?
        envelope.mark_as_dead(error_message)
        if @adapter.responds_to?(:mark_dead)
          @adapter.mark_dead(envelope.id, error_message)
        else
          @adapter.mark_failed(envelope.id, error_message)
        end
        Log.error { "Job #{envelope.id} (#{envelope.job_class}) is dead after #{envelope.attempts} attempts" }
      else
        # Calculate backoff and re-enqueue
        backoff = calculate_backoff(envelope)
        envelope.schedule_retry(backoff)
        @adapter.enqueue(envelope)

        Log.info { "Job #{envelope.id} (#{envelope.job_class}) scheduled for retry in #{backoff}" }
      end
    end

    # Calculates the retry backoff for a given envelope.
    #
    # Attempts to use the job class's custom backoff strategy if available,
    # falling back to the default exponential backoff (2^attempts seconds).
    private def calculate_backoff(envelope : JobEnvelope) : Time::Span
      # Default exponential backoff: 2^attempts seconds
      (2 ** envelope.attempts).seconds
    end

    # Returns true if the HTTP server has no pending requests.
    private def is_server_idle? : Bool
      @@pending_request_mutex.synchronize do
        @@pending_request_count <= 0
      end
    end
  end
end
