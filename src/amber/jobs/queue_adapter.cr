require "./job_envelope"

module Amber::Jobs
  # Abstract base class for job queue storage adapters.
  #
  # All queue storage implementations should inherit from this class and implement
  # the required abstract methods. This allows the Amber jobs system to work with
  # any backend storage system (in-memory, Redis, database, etc.) through a unified
  # interface.
  #
  # ## Built-in Adapters
  #
  # - `MemoryQueueAdapter` - Thread-safe in-memory queue (default, always available)
  #
  # ## Example Custom Adapter
  #
  # ```
  # class RedisQueueAdapter < Amber::Jobs::QueueAdapter
  #   def initialize(@redis : Redis::Client)
  #   end
  #
  #   def enqueue(envelope : JobEnvelope)
  #     @redis.lpush("queue:#{envelope.queue}", envelope.to_json)
  #   end
  #
  #   # ... implement other abstract methods
  # end
  # ```
  abstract class QueueAdapter
    # Adds a job envelope to the queue for processing.
    abstract def enqueue(envelope : JobEnvelope) : Nil

    # Removes and returns the next ready job from the specified queue.
    # Returns nil if the queue is empty or no jobs are ready.
    abstract def dequeue(queue : String) : JobEnvelope?

    # Schedules a job envelope for execution at a specific time.
    abstract def schedule(envelope : JobEnvelope, at : Time) : Nil

    # Returns the number of pending jobs in the specified queue.
    abstract def size(queue : String) : Int32

    # Removes all jobs from the specified queue.
    abstract def clear(queue : String) : Nil

    # Marks a job as completed by its ID.
    abstract def mark_completed(id : String) : Nil

    # Marks a job as failed by its ID, recording the error message.
    abstract def mark_failed(id : String, error : String) : Nil

    # Re-enqueues a failed job for retry by its ID.
    abstract def retry_failed(id : String) : Nil

    # Returns all jobs that have been marked as dead (exceeded max retries).
    abstract def dead_jobs : Array(JobEnvelope)

    # Returns all jobs across all queues. Useful for monitoring and inspection.
    abstract def all_jobs : Array(JobEnvelope)

    # Optional lifecycle methods with default implementations

    # Called when the adapter is being shut down.
    # Override this method to perform cleanup operations.
    def close : Nil
      # Default implementation does nothing
    end

    # Returns true if the adapter is healthy and ready to handle operations.
    # Override this method to implement health checks for your storage backend.
    def healthy? : Bool
      true
    end
  end
end
