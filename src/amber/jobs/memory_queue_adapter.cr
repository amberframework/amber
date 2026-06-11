require "./queue_adapter"

module Amber::Jobs
  # In-memory implementation of QueueAdapter.
  #
  # This adapter stores jobs in memory using Mutex-protected data structures and
  # provides scheduled job support via a sorted collection checked during dequeue.
  # This is the default queue adapter and is suitable for development, testing,
  # and single-instance applications.
  #
  # **Note**: Job data will be lost when the application restarts since everything
  # is stored in memory. For production applications that require persistence or
  # multi-instance deployments, consider using a Redis-based or database adapter.
  #
  # ## Thread Safety
  #
  # All operations are protected by a Mutex to ensure safe concurrent access
  # from multiple fibers.
  #
  # ## Usage
  #
  # ```
  # adapter = Amber::Jobs::MemoryQueueAdapter.new
  # adapter.enqueue(envelope)
  # job = adapter.dequeue("default")
  # ```
  class MemoryQueueAdapter < QueueAdapter
    @queues : Hash(String, Deque(JobEnvelope))
    @scheduled : Array(JobEnvelope)
    @completed : Hash(String, JobEnvelope)
    @failed : Hash(String, JobEnvelope)
    @dead : Hash(String, JobEnvelope)
    @all_envelopes : Hash(String, JobEnvelope)
    @mutex : Mutex

    def initialize
      @queues = Hash(String, Deque(JobEnvelope)).new
      @scheduled = Array(JobEnvelope).new
      @completed = Hash(String, JobEnvelope).new
      @failed = Hash(String, JobEnvelope).new
      @dead = Hash(String, JobEnvelope).new
      @all_envelopes = Hash(String, JobEnvelope).new
      @mutex = Mutex.new
    end

    # Adds a job envelope to the appropriate queue.
    #
    # If the envelope's `scheduled_at` is in the future, it is placed in the
    # scheduled set instead of the immediate queue. Otherwise, it is appended
    # to the back of the named queue.
    def enqueue(envelope : JobEnvelope) : Nil
      @mutex.synchronize do
        @all_envelopes[envelope.id] = envelope

        if envelope.scheduled_at > Time.utc
          @scheduled << envelope
          @scheduled.sort_by!(&.scheduled_at)
        else
          queue = ensure_queue(envelope.queue)
          queue.push(envelope)
        end
      end
    end

    # Removes and returns the next ready job from the specified queue.
    #
    # Before checking the immediate queue, this method promotes any scheduled
    # jobs whose `scheduled_at` time has passed into their respective queues.
    # Returns nil if no jobs are ready.
    def dequeue(queue : String) : JobEnvelope?
      @mutex.synchronize do
        promote_scheduled_jobs
        q = @queues[queue]?
        return nil unless q

        envelope = q.shift?
        return nil unless envelope
        envelope
      end
    end

    # Schedules a job envelope for execution at a specific time.
    #
    # Updates the envelope's `scheduled_at` and places it in the scheduled set.
    def schedule(envelope : JobEnvelope, at : Time) : Nil
      @mutex.synchronize do
        envelope.scheduled_at = at
        @all_envelopes[envelope.id] = envelope
        @scheduled << envelope
        @scheduled.sort_by!(&.scheduled_at)
      end
    end

    # Returns the number of pending jobs in the specified queue.
    #
    # This counts only jobs in the immediate queue, not scheduled jobs.
    def size(queue : String) : Int32
      @mutex.synchronize do
        q = @queues[queue]?
        return 0 unless q
        q.size.to_i32
      end
    end

    # Removes all jobs from the specified queue.
    def clear(queue : String) : Nil
      @mutex.synchronize do
        if q = @queues[queue]?
          q.each { |env| @all_envelopes.delete(env.id) }
          q.clear
        end

        # Also remove scheduled jobs for this queue
        removed_ids = [] of String
        @scheduled.reject! do |env|
          if env.queue == queue
            removed_ids << env.id
            true
          else
            false
          end
        end
        removed_ids.each { |id| @all_envelopes.delete(id) }
      end
    end

    # Marks a job as completed by its ID.
    def mark_completed(id : String) : Nil
      @mutex.synchronize do
        if envelope = @all_envelopes[id]?
          envelope.mark_as_completed
          @completed[id] = envelope
          @failed.delete(id)
        end
      end
    end

    # Marks a job as failed by its ID, recording the error message.
    def mark_failed(id : String, error : String) : Nil
      @mutex.synchronize do
        if envelope = @all_envelopes[id]?
          envelope.mark_as_failed(error)
          @failed[id] = envelope
        end
      end
    end

    # Re-enqueues a failed job for retry by its ID.
    #
    # Resets the job's status to Pending and places it back in the immediate queue.
    # If the job is not found in the failed set, this is a no-op.
    def retry_failed(id : String) : Nil
      @mutex.synchronize do
        if envelope = @failed.delete(id)
          envelope.status = JobEnvelope::Status::Pending
          queue = ensure_queue(envelope.queue)
          queue.push(envelope)
        end
      end
    end

    # Returns all jobs that have been marked as dead (exceeded max retries).
    def dead_jobs : Array(JobEnvelope)
      @mutex.synchronize do
        @dead.values.dup
      end
    end

    # Returns all tracked job envelopes across all states.
    def all_jobs : Array(JobEnvelope)
      @mutex.synchronize do
        @all_envelopes.values.dup
      end
    end

    # Marks a job as dead. Called when a job has exceeded its max retries.
    def mark_dead(id : String, error : String) : Nil
      @mutex.synchronize do
        if envelope = @all_envelopes[id]?
          envelope.mark_as_dead(error)
          @dead[id] = envelope
          @failed.delete(id)
        end
      end
    end

    # Returns the number of scheduled jobs across all queues.
    def scheduled_size : Int32
      @mutex.synchronize do
        @scheduled.size.to_i32
      end
    end

    # Returns the number of completed jobs.
    def completed_size : Int32
      @mutex.synchronize do
        @completed.size.to_i32
      end
    end

    # Returns the number of failed jobs.
    def failed_size : Int32
      @mutex.synchronize do
        @failed.size.to_i32
      end
    end

    # Returns the number of dead jobs.
    def dead_size : Int32
      @mutex.synchronize do
        @dead.size.to_i32
      end
    end

    # Closes the adapter and cleans up resources.
    def close : Nil
      @mutex.synchronize do
        @queues.clear
        @scheduled.clear
        @completed.clear
        @failed.clear
        @dead.clear
        @all_envelopes.clear
      end
    end

    # Promotes any scheduled jobs that are now ready to run into their queues.
    private def promote_scheduled_jobs : Nil
      now = Time.utc
      promoted = [] of Int32

      @scheduled.each_with_index do |envelope, index|
        # Since scheduled is sorted by scheduled_at, we can stop early
        break if envelope.scheduled_at > now
        promoted << index

        queue = ensure_queue(envelope.queue)
        queue.push(envelope)
      end

      # Remove promoted jobs in reverse order to maintain indices
      promoted.reverse_each do |index|
        @scheduled.delete_at(index)
      end
    end

    # Returns the queue Deque for the given name, creating it if necessary.
    private def ensure_queue(name : String) : Deque(JobEnvelope)
      @queues[name] ||= Deque(JobEnvelope).new
    end
  end
end
