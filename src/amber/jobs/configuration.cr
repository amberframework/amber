module Amber::Jobs
  # Configuration settings for the background jobs system.
  #
  # This class holds all configurable options for job processing, including
  # the adapter type, queue names, worker count, polling interval, and
  # work-stealing behavior.
  #
  # ## Usage
  #
  # Configuration is typically set through `Amber::Server.configure`:
  #
  # ```
  # Amber::Server.configure do |app|
  #   app.jobs.adapter = :memory
  #   app.jobs.queues = ["default", "critical", "low"]
  #   app.jobs.workers = 2
  #   app.jobs.work_stealing_enabled = true
  #   app.jobs.polling_interval = 1.second
  # end
  # ```
  #
  # Or accessed directly:
  #
  # ```
  # config = Amber::Jobs.configuration
  # config.workers = 4
  # ```
  class Configuration
    # The adapter type for job queue storage.
    # Default: :memory
    property adapter : Symbol = :memory

    # The list of queue names to process, in priority order.
    # Workers will check queues in this order, processing the first available job.
    # Default: ["default"]
    property list_of_queues : Array(String) = ["default"]

    # The number of worker fibers to spawn.
    # Default: 1
    property number_of_workers : Int32 = 1

    # Whether idle web server instances should process background jobs.
    # When enabled, the web server spawns additional workers that only pick up
    # jobs when no HTTP requests are pending.
    # Default: false
    property? is_work_stealing_enabled : Bool = false

    # How frequently workers poll the queue adapter for available jobs.
    # Default: 1.second
    property polling_interval : Time::Span = 1.second

    # How frequently the scheduler checks for jobs ready to be promoted.
    # Default: 5.seconds
    property scheduler_interval : Time::Span = 5.seconds

    # Whether the jobs system should automatically start workers when
    # the Amber server starts.
    # Default: false
    property? is_auto_start_enabled : Bool = false

    def initialize
    end

    # Convenience setter that accepts an array of strings for queue names.
    def queues=(list_of_queues : Array(String))
      @list_of_queues = list_of_queues
    end

    # Convenience getter that returns queue names.
    def queues : Array(String)
      @list_of_queues
    end

    # Convenience setter for number of workers.
    def workers=(count : Int32)
      @number_of_workers = count
    end

    # Convenience getter for number of workers.
    def workers : Int32
      @number_of_workers
    end

    # Convenience setter for work stealing.
    def work_stealing_enabled=(value : Bool)
      @is_work_stealing_enabled = value
    end

    # Convenience getter for work stealing.
    def work_stealing_enabled? : Bool
      @is_work_stealing_enabled
    end
  end
end
