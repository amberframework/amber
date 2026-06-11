# Background Jobs

Amber::Jobs provides in-process background job processing for tasks that should not block HTTP request handling. Jobs are defined as classes with a `perform` method, serialized to JSON for queue storage, and executed by configurable worker fibers. Use background jobs for sending emails, processing uploads, calling external APIs, or any work that takes more than a few hundred milliseconds.

## Quick Start

```crystal
# Define a job
class SendWelcomeEmail < Amber::Jobs::Job
  include JSON::Serializable

  property user_id : Int64

  def initialize(@user_id : Int64)
  end

  def perform
    user = User.find(user_id)
    WelcomeMailer.new(user.name, user.email)
      .to(user.email)
      .subject("Welcome!")
      .deliver
  end
end

# Register the job class (required for deserialization)
Amber::Jobs.register(SendWelcomeEmail)

# Enqueue a job
SendWelcomeEmail.new(user_id: 42_i64).enqueue
```

## Defining Jobs

Every job must inherit from `Amber::Jobs::Job`, include `JSON::Serializable`, and implement the abstract `perform` method. Any instance variables decorated with `property` will be serialized when the job is enqueued and deserialized when executed.

```crystal
class ProcessUpload < Amber::Jobs::Job
  include JSON::Serializable

  property file_path : String
  property user_id : Int64

  def initialize(@file_path : String, @user_id : Int64)
  end

  def perform
    # Your processing logic here
  end
end
```

### Job Registration

Every job class must be registered with the Amber::Jobs system so the worker can reconstruct the job instance from its serialized JSON payload:

```crystal
Amber::Jobs.register(ProcessUpload)
Amber::Jobs.register(SendWelcomeEmail)
```

Registration is typically done at application startup, before any jobs are enqueued or workers are started.

### Customizing Queue and Retry Behavior

Override class methods to customize per-job behavior:

```crystal
class CriticalNotification < Amber::Jobs::Job
  include JSON::Serializable

  property message : String

  def initialize(@message : String)
  end

  def perform
    # Send critical notification
  end

  # Override the default queue name (default: "default")
  def self.queue : String
    "critical"
  end

  # Override the maximum retry attempts (default: 3)
  def self.max_retries : Int32
    5
  end

  # Override the retry backoff strategy (default: exponential 2^attempt seconds)
  def self.retry_backoff(attempt : Int32) : Time::Span
    (attempt * 10).seconds  # Linear backoff: 10s, 20s, 30s, ...
  end
end
```

## Enqueueing Jobs

The `enqueue` method places the job in the queue for background processing. It returns a `JobEnvelope` containing the job's metadata.

```crystal
# Enqueue to the default queue
SendWelcomeEmail.new(user_id: 42_i64).enqueue

# Enqueue with a delay
SendWelcomeEmail.new(user_id: 42_i64).enqueue(delay: 5.minutes)

# Enqueue to a specific queue (overrides the class default)
SendWelcomeEmail.new(user_id: 42_i64).enqueue(queue: "low_priority")

# Capture the envelope for tracking
envelope = SendWelcomeEmail.new(user_id: 42_i64).enqueue
puts envelope.id       # UUID string
puts envelope.status   # JobEnvelope::Status::Pending
```

### JobEnvelope

The `JobEnvelope` struct wraps a job with metadata for queue management:

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique UUID for this job instance |
| `job_class` | `String` | Fully qualified Crystal class name |
| `payload` | `String` | JSON-serialized job data |
| `queue` | `String` | Queue name (e.g., "default", "critical") |
| `attempts` | `Int32` | Number of execution attempts so far |
| `max_retries` | `Int32` | Maximum retry attempts before marking dead |
| `scheduled_at` | `Time` | When the job should execute |
| `created_at` | `Time` | When the job was originally enqueued |
| `status` | `Status` | Current lifecycle status (Pending, Running, Completed, Failed, Dead) |
| `last_error` | `String?` | Error message from the most recent failure |

## Configuration

Configuration is set through the `Amber::Jobs` module:

```crystal
Amber::Jobs.configure do |config|
  config.adapter = :memory
  config.queues = ["default", "critical", "low"]
  config.workers = 2
  config.polling_interval = 1.second
  config.scheduler_interval = 5.seconds
  config.work_stealing_enabled = true
  config.is_auto_start_enabled = true
end
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `adapter` | `:memory` | Queue storage backend |
| `list_of_queues` / `queues` | `["default"]` | Queue names in priority order |
| `number_of_workers` / `workers` | `1` | Number of worker fibers |
| `polling_interval` | `1.second` | How often workers check for jobs |
| `scheduler_interval` | `5.seconds` | How often the scheduler promotes delayed jobs |
| `is_work_stealing_enabled` / `work_stealing_enabled` | `false` | Enable idle-server job processing |
| `is_auto_start_enabled` | `false` | Auto-start workers when Amber server starts |

### YAML Configuration

Jobs can also be configured via your environment YAML files:

```yaml
jobs:
  adapter: "memory"
  workers: 2
  auto_start: true
  polling_interval_seconds: 1.0
  scheduler_interval_seconds: 5.0
  work_stealing: false
```

All jobs configuration values can be overridden with environment variables:

```bash
AMBER_JOBS_ADAPTER=memory
AMBER_JOBS_WORKERS=4
AMBER_JOBS_AUTO_START=true
AMBER_JOBS_POLLING_INTERVAL_SECONDS=0.5
AMBER_JOBS_WORK_STEALING=true
```

## Workers

Workers run in background fibers, polling configured queues for available jobs. They check queues in priority order, processing the first available job found.

```crystal
# Workers are created and started automatically by Amber::Jobs.start
# Manual worker creation (for advanced use):
worker = Amber::Jobs::Worker.new(
  adapter: Amber::Jobs.adapter,
  list_of_queues: ["critical", "default", "low"],
  polling_interval: 1.second
)
worker.start
```

### Work Stealing

When work stealing is enabled, the system spawns additional workers that only process jobs when no HTTP requests are pending. This allows idle web server instances to contribute to job processing without impacting request latency.

```crystal
Amber::Jobs.configure do |config|
  config.work_stealing_enabled = true
end
```

The work-stealing worker monitors `Worker.pending_request_count` (a class-level atomic counter) and only dequeues jobs when this count is zero.

## Scheduler

The Scheduler runs in a background fiber and periodically checks for delayed or scheduled jobs that are ready to execute. In the `MemoryQueueAdapter`, scheduled job promotion also happens during dequeue, so the scheduler serves as an additional safety check.

```crystal
scheduler = Amber::Jobs::Scheduler.new(
  adapter: Amber::Jobs.adapter,
  interval: 5.seconds
)
scheduler.start
```

The scheduler is started automatically when you call `Amber::Jobs.start`.

## Queue Adapters

### MemoryQueueAdapter (Default)

The built-in `MemoryQueueAdapter` stores jobs in memory using Mutex-protected data structures. It supports scheduled jobs, completion tracking, failure tracking, and dead job management.

Suitable for: development, testing, and single-instance applications.

Limitations: job data is lost when the application restarts.

### Writing a Custom Adapter

Inherit from `Amber::Jobs::QueueAdapter` and implement all abstract methods:

```crystal
class RedisQueueAdapter < Amber::Jobs::QueueAdapter
  def initialize(@redis : Redis::Client)
  end

  def enqueue(envelope : JobEnvelope) : Nil
    @redis.lpush("queue:#{envelope.queue}", envelope.to_json)
  end

  def dequeue(queue : String) : JobEnvelope?
    if data = @redis.rpop("queue:#{queue}")
      JobEnvelope.from_json(data)
    end
  end

  def schedule(envelope : JobEnvelope, at : Time) : Nil
    @redis.zadd("scheduled", at.to_unix.to_f, envelope.to_json)
  end

  def size(queue : String) : Int32
    @redis.llen("queue:#{queue}").to_i32
  end

  def clear(queue : String) : Nil
    @redis.del("queue:#{queue}")
  end

  def mark_completed(id : String) : Nil
    @redis.hset("completed", id, Time.utc.to_rfc3339)
  end

  def mark_failed(id : String, error : String) : Nil
    @redis.hset("failed", id, error)
  end

  def retry_failed(id : String) : Nil
    if data = @redis.hdel("failed", id)
      # Re-enqueue logic
    end
  end

  def dead_jobs : Array(JobEnvelope)
    [] of JobEnvelope
  end

  def all_jobs : Array(JobEnvelope)
    [] of JobEnvelope
  end
end

# Set the custom adapter
Amber::Jobs.adapter = RedisQueueAdapter.new(Redis::Client.new)
```

### QueueAdapter Abstract Methods

| Method | Description |
|--------|-------------|
| `enqueue(envelope)` | Add a job to the queue |
| `dequeue(queue)` | Remove and return the next ready job, or nil |
| `schedule(envelope, at)` | Schedule a job for future execution |
| `size(queue)` | Count of pending jobs in a queue |
| `clear(queue)` | Remove all jobs from a queue |
| `mark_completed(id)` | Mark a job as completed |
| `mark_failed(id, error)` | Mark a job as failed |
| `retry_failed(id)` | Re-enqueue a failed job |
| `dead_jobs` | Return all dead jobs |
| `all_jobs` | Return all tracked jobs |
| `close` | Optional cleanup on shutdown |
| `healthy?` | Optional health check (default: true) |

## Starting and Stopping

```crystal
# Start the jobs system (workers + scheduler)
Amber::Jobs.start

# Stop all workers and the scheduler
Amber::Jobs.stop

# Reset state (useful in tests)
Amber::Jobs.reset
```

When `is_auto_start_enabled` is true in configuration, `Amber::Jobs.start` is called automatically when the Amber server starts.

## Testing Jobs

Test jobs by calling `perform` directly or by using the `MemoryQueueAdapter` to verify enqueueing behavior:

```crystal
describe SendWelcomeEmail do
  before_each do
    Amber::Jobs.reset
    Amber::Jobs.register(SendWelcomeEmail)
  end

  it "performs the job" do
    job = SendWelcomeEmail.new(user_id: 1_i64)
    # Call perform directly to test the job logic
    job.perform
  end

  it "enqueues to the correct queue" do
    envelope = SendWelcomeEmail.new(user_id: 1_i64).enqueue
    envelope.queue.should eq("default")
  end

  it "enqueues with delay" do
    envelope = SendWelcomeEmail.new(user_id: 1_i64).enqueue(delay: 5.minutes)
    envelope.scheduled_at.should be > Time.utc
  end

  it "processes through the worker" do
    SendWelcomeEmail.new(user_id: 1_i64).enqueue

    worker = Amber::Jobs::Worker.new(
      adapter: Amber::Jobs.adapter,
      list_of_queues: ["default"]
    )
    worker.process_next_job.should be_true
    worker.jobs_processed.should eq(1)
  end
end
```

## Source Files

- `src/amber/jobs.cr` -- Module entry point, registry, start/stop
- `src/amber/jobs/job.cr` -- Abstract Job base class
- `src/amber/jobs/job_envelope.cr` -- JobEnvelope struct with lifecycle management
- `src/amber/jobs/worker.cr` -- Worker fiber with polling and retry logic
- `src/amber/jobs/scheduler.cr` -- Scheduler fiber for delayed job promotion
- `src/amber/jobs/configuration.cr` -- Configuration class
- `src/amber/jobs/queue_adapter.cr` -- Abstract QueueAdapter base class
- `src/amber/jobs/memory_queue_adapter.cr` -- In-memory adapter implementation
