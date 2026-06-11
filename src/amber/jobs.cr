require "./jobs/job_envelope"
require "./jobs/queue_adapter"
require "./jobs/memory_queue_adapter"
require "./jobs/configuration"
require "./jobs/scheduler"
require "./jobs/worker"
require "./jobs/job"

module Amber::Jobs
  Log = ::Log.for(self)

  # The global job registry maps job class names to deserialization procs.
  # Jobs register themselves using the `Amber::Jobs.register` macro.
  @@job_registry = Hash(String, Proc(String, Job)).new

  # The singleton queue adapter instance.
  @@adapter : QueueAdapter?

  # The singleton configuration instance.
  @@configuration : Configuration?

  # The list of active workers.
  @@list_of_workers = Array(Worker).new

  # The scheduler instance.
  @@scheduler : Scheduler?

  # Returns the current queue adapter, creating a default MemoryQueueAdapter if none is set.
  def self.adapter : QueueAdapter
    @@adapter ||= create_adapter_from_configuration
  end

  # Sets the queue adapter instance directly.
  def self.adapter=(adapter : QueueAdapter)
    @@adapter = adapter
  end

  # Returns the current configuration, creating a default if none exists.
  def self.configuration : Configuration
    @@configuration ||= Configuration.new
  end

  # Sets the configuration directly.
  def self.configuration=(config : Configuration)
    @@configuration = config
  end

  # Yields the configuration for modification.
  def self.configure(&)
    yield configuration
  end

  # Registers a job class for deserialization.
  #
  # This must be called for each job class so the worker can reconstruct
  # the job instance from its serialized JSON payload.
  #
  # ## Usage
  #
  # ```
  # Amber::Jobs.register(MyJob)
  # ```
  macro register(job_class)
    Amber::Jobs.register_job({{job_class.stringify}}) do |payload|
      {{job_class}}.from_json(payload).as(Amber::Jobs::Job)
    end
  end

  # Registers a job class with a deserialization proc.
  # This is the runtime method called by the `register` macro.
  def self.register_job(class_name : String, &block : String -> Job)
    @@job_registry[class_name] = block
  end

  # Deserializes a job from its class name and JSON payload.
  # Returns nil if the job class is not registered.
  def self.deserialize(class_name : String, payload : String) : Job?
    factory = @@job_registry[class_name]?
    return nil unless factory

    begin
      factory.call(payload)
    rescue ex
      Log.error(exception: ex) { "Failed to deserialize job: #{class_name}" }
      nil
    end
  end

  # Starts the background jobs system.
  #
  # Spawns the configured number of workers and starts the scheduler.
  # This is typically called automatically when the Amber server starts
  # if `is_auto_start_enabled` is true in the configuration.
  def self.start : Nil
    config = configuration

    # Start workers
    config.number_of_workers.times do
      worker = Worker.new(
        adapter: adapter,
        list_of_queues: config.list_of_queues,
        polling_interval: config.polling_interval,
      )
      worker.start
      @@list_of_workers << worker
    end

    # Start work-stealing workers if enabled
    if config.is_work_stealing_enabled?
      stealing_worker = Worker.new(
        adapter: adapter,
        list_of_queues: config.list_of_queues,
        polling_interval: config.polling_interval,
        idle_only: true,
      )
      stealing_worker.start
      @@list_of_workers << stealing_worker
    end

    # Start the scheduler
    @@scheduler = Scheduler.new(
      adapter: adapter,
      interval: config.scheduler_interval,
    )
    @@scheduler.try(&.start)

    Log.info { "Background jobs system started with #{@@list_of_workers.size} worker(s)" }
  end

  # Stops all workers and the scheduler.
  def self.stop : Nil
    @@list_of_workers.each(&.stop)
    @@list_of_workers.clear
    @@scheduler.try(&.stop)
    @@scheduler = nil

    Log.info { "Background jobs system stopped" }
  end

  # Resets the jobs system state. Primarily useful for testing.
  def self.reset : Nil
    stop
    @@adapter = nil
    @@configuration = nil
    @@job_registry.clear
  end

  # Creates the appropriate adapter based on the current configuration.
  private def self.create_adapter_from_configuration : QueueAdapter
    case configuration.adapter
    when :memory
      MemoryQueueAdapter.new
    else
      raise ArgumentError.new(
        "Unknown jobs queue adapter: #{configuration.adapter}. " \
        "Available: :memory. Register custom adapters by setting " \
        "Amber::Jobs.adapter directly."
      )
    end
  end
end
