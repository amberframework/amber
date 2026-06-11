require "json"
require "uuid"

module Amber::Jobs
  # Wraps a job with metadata for queue management.
  #
  # A JobEnvelope carries all the information needed to track, schedule, retry,
  # and execute a job within the background processing system. It acts as the
  # transport container that moves through the queue adapter, worker, and scheduler.
  #
  # ## Fields
  #
  # - `id` - A unique UUID identifying this job instance
  # - `job_class` - The fully qualified Crystal class name for deserialization
  # - `payload` - JSON-serialized job data (constructor arguments)
  # - `queue` - The queue this job belongs to (e.g., "default", "critical")
  # - `attempts` - How many times this job has been attempted
  # - `max_retries` - Maximum number of retry attempts before the job is marked dead
  # - `scheduled_at` - When the job should be executed (supports delayed execution)
  # - `created_at` - When the job was originally enqueued
  # - `status` - Current lifecycle status of the job
  # - `last_error` - The error message from the most recent failed attempt, if any
  struct JobEnvelope
    include JSON::Serializable

    enum Status
      Pending
      Running
      Completed
      Failed
      Dead
    end

    property id : String
    property job_class : String
    property payload : String
    property queue : String
    property attempts : Int32
    property max_retries : Int32
    property scheduled_at : Time
    property created_at : Time
    property status : Status
    property last_error : String?

    def initialize(
      @job_class : String,
      @payload : String,
      @queue : String = "default",
      @max_retries : Int32 = 3,
      @scheduled_at : Time = Time.utc,
      @status : Status = Status::Pending,
    )
      @id = UUID.random.to_s
      @attempts = 0
      @created_at = Time.utc
      @last_error = nil
    end

    # Returns true if the job is ready to be executed based on its scheduled time.
    def is_ready_to_run? : Bool
      @status == Status::Pending && Time.utc >= @scheduled_at
    end

    # Returns true if the job has exceeded its maximum retry attempts.
    def has_exceeded_max_retries? : Bool
      @attempts >= @max_retries
    end

    # Increments the attempt counter and sets the status to Running.
    def mark_as_running : Nil
      @attempts += 1
      @status = Status::Running
    end

    # Sets the status to Completed.
    def mark_as_completed : Nil
      @status = Status::Completed
    end

    # Sets the status to Failed with an error message.
    def mark_as_failed(error : String) : Nil
      @status = Status::Failed
      @last_error = error
    end

    # Sets the status to Dead (exceeded max retries, will not be retried).
    def mark_as_dead(error : String) : Nil
      @status = Status::Dead
      @last_error = error
    end

    # Resets the status to Pending for retry, updating the scheduled time
    # based on exponential backoff.
    def schedule_retry(backoff : Time::Span) : Nil
      @status = Status::Pending
      @scheduled_at = Time.utc + backoff
    end
  end
end
