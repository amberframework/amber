require "json"
require "./job_envelope"

module Amber::Jobs
  # Abstract base class for all background jobs.
  #
  # To define a job, inherit from this class, include `JSON::Serializable`, and
  # implement the `perform` method. Any instance variables decorated with
  # `JSON::Field` will be serialized when the job is enqueued and deserialized
  # when the job is executed.
  #
  # ## Example
  #
  # ```
  # class SendWelcomeEmail < Amber::Jobs::Job
  #   include JSON::Serializable
  #
  #   property user_id : Int64
  #
  #   def initialize(@user_id : Int64)
  #   end
  #
  #   def perform
  #     user = User.find(user_id)
  #     Mailer.send_welcome(user)
  #   end
  #
  #   def self.queue : String
  #     "mailers"
  #   end
  # end
  # ```
  #
  # ## Enqueueing
  #
  # ```
  # SendWelcomeEmail.new(user_id: 42_i64).enqueue
  # SendWelcomeEmail.new(user_id: 42_i64).enqueue(delay: 5.minutes)
  # SendWelcomeEmail.new(user_id: 42_i64).enqueue(queue: "critical")
  # ```
  #
  # ## Configuration
  #
  # Override class methods to customize job behavior:
  #
  # - `self.queue` - The queue name (default: "default")
  # - `self.max_retries` - Maximum retry attempts (default: 3)
  # - `self.retry_backoff(attempt)` - Backoff duration per attempt (default: exponential)
  abstract class Job
    # Override this method to define the job's work.
    abstract def perform

    # The queue name this job class should be enqueued to by default.
    def self.queue : String
      "default"
    end

    # Maximum number of retry attempts before the job is marked as dead.
    def self.max_retries : Int32
      3
    end

    # Calculates the retry backoff duration for the given attempt number.
    # Uses exponential backoff by default: 2^attempt seconds.
    #
    # Override this to implement custom backoff strategies.
    def self.retry_backoff(attempt : Int32) : Time::Span
      (2 ** attempt).seconds
    end

    # Enqueues this job for background processing.
    #
    # - `queue` - Override the default queue for this specific enqueue
    # - `delay` - Delay execution by the specified duration
    def enqueue(queue : String? = nil, delay : Time::Span? = nil) : JobEnvelope
      resolved_queue = queue || self.class.queue
      scheduled_at = delay ? Time.utc + delay : Time.utc

      envelope = JobEnvelope.new(
        job_class: self.class.name,
        payload: serialize_to_json,
        queue: resolved_queue,
        max_retries: self.class.max_retries,
        scheduled_at: scheduled_at,
      )

      Amber::Jobs.adapter.enqueue(envelope)
      envelope
    end

    # Serializes the job instance to JSON for storage in the queue.
    # Subclasses must include JSON::Serializable for this to work.
    private def serialize_to_json : String
      if self.responds_to?(:to_json)
        self.to_json
      else
        "{}"
      end
    end
  end
end
