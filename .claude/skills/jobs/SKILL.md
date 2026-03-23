---
name: amber-jobs
description: Amber V2 background jobs — job definition, work-stealing, retry logic, queue adapters, enqueuing
user-invocable: false
---

# Amber Background Jobs

Amber V2 includes a built-in background jobs system with queue-based processing, automatic retries with exponential backoff, work-stealing from idle web instances, and a pluggable adapter interface. Jobs run in Crystal fibers alongside the web server -- no separate worker process is required.

## Defining a Job

Inherit from `Amber::Jobs::Job`, include `JSON::Serializable`, and implement the `perform` method. Any instance variables become the job's serialized arguments.

```crystal
class SendWelcomeEmail < Amber::Jobs::Job
  include JSON::Serializable

  property user_id : Int64

  def initialize(@user_id : Int64)
  end

  def perform
    user = User.find(user_id)
    Mailer.send_welcome(user)
  end
end
```

Every job class must be registered so the worker can deserialize it from JSON:

```crystal
Amber::Jobs.register(SendWelcomeEmail)
```

### Customizing Job Behavior

Override class methods to control queue routing, retry limits, and backoff strategy:

```crystal
class ImportCsvData < Amber::Jobs::Job
  include JSON::Serializable

  property file_path : String

  def initialize(@file_path : String)
  end

  def perform
    # Long-running import logic
  end

  # Route to a named queue instead of "default"
  def self.queue : String
    "imports"
  end

  # Allow more retry attempts (default is 3)
  def self.max_retries : Int32
    5
  end

  # Custom backoff: linear 30-second intervals instead of exponential
  def self.retry_backoff(attempt : Int32) : Time::Span
    (30 * attempt).seconds
  end
end
```

| Class Method | Default | Purpose |
|---|---|---|
| `self.queue` | `"default"` | Queue name the job is enqueued to |
| `self.max_retries` | `3` | Maximum attempts before the job is marked dead |
| `self.retry_backoff(attempt)` | `(2 ** attempt).seconds` | Backoff duration per attempt (exponential) |

## Enqueuing Jobs

Call `enqueue` on a job instance. The job is serialized to JSON and pushed to the queue adapter.

```crystal
# Immediate execution
SendWelcomeEmail.new(user_id: 42_i64).enqueue

# Delayed execution — runs after 5 minutes
SendWelcomeEmail.new(user_id: 42_i64).enqueue(delay: 5.minutes)

# Override queue for this specific enqueue
SendWelcomeEmail.new(user_id: 42_i64).enqueue(queue: "critical")

# Both delay and queue override
SendWelcomeEmail.new(user_id: 42_i64).enqueue(delay: 1.hour, queue: "low")
```

`enqueue` returns a `JobEnvelope` containing the job's UUID and metadata, which can be used for tracking:

```crystal
envelope = SendWelcomeEmail.new(user_id: 42_i64).enqueue
Log.info { "Enqueued job #{envelope.id} on queue #{envelope.queue}" }
```

## JobEnvelope

The `JobEnvelope` struct wraps every job with tracking metadata as it moves through the system.

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Unique UUID for this job instance |
| `job_class` | `String` | Fully qualified Crystal class name |
| `payload` | `String` | JSON-serialized job arguments |
| `queue` | `String` | Queue this job belongs to |
| `attempts` | `Int32` | Number of execution attempts so far |
| `max_retries` | `Int32` | Maximum retry attempts before dead |
| `scheduled_at` | `Time` | When the job becomes eligible to run |
| `created_at` | `Time` | When the job was originally enqueued |
| `status` | `Status` | Current lifecycle state |
| `last_error` | `String?` | Error message from most recent failure |

### Job Lifecycle States

The `JobEnvelope::Status` enum tracks each job through its lifecycle:

```
Pending -> Running -> Completed
                  \-> Failed -> Pending (retry)
                            \-> Dead (max retries exceeded)
```

- **Pending** -- Waiting in queue or scheduled for future execution
- **Running** -- Currently being executed by a worker
- **Completed** -- Finished successfully
- **Failed** -- Execution raised an exception (may be retried)
- **Dead** -- Exceeded `max_retries`, will not be retried

## Retry Logic

When `perform` raises an exception, the worker automatically handles retries:

1. The attempt counter is incremented
2. If `attempts >= max_retries`, the job is marked **Dead** and will not run again
3. Otherwise, the job is re-enqueued with a backoff delay calculated by the job class's `self.retry_backoff(attempt)` method
4. The default backoff is exponential: 2s, 4s, 8s, 16s, etc. (`(2 ** attempt).seconds`)
5. The `last_error` field on the envelope records the exception class and message

The worker logs retries at `info` level and dead jobs at `error` level.

## Work-Stealing

Work-stealing allows idle web server instances to process background jobs without impacting request latency. When enabled, an additional worker fiber is spawned that only dequeues jobs when no HTTP requests are pending.

The worker checks `Worker.pending_request_count` (maintained by the HTTP server middleware) before polling. If the count is greater than zero, the work-stealing worker sleeps and tries again at the next polling interval.

```crystal
Amber::Jobs.configure do |config|
  config.work_stealing_enabled = true
end
```

This is useful for deployments with multiple web instances where some may be idle during low-traffic periods. Those idle instances automatically contribute to job throughput.

## Configuration

### Programmatic Configuration

```crystal
Amber::Jobs.configure do |config|
  config.adapter = :memory                    # Queue adapter (:memory is built-in)
  config.queues = ["default", "critical", "low"]  # Queue names in priority order
  config.workers = 2                          # Number of worker fibers
  config.work_stealing_enabled = true         # Enable work-stealing
  config.polling_interval = 1.second          # How often workers poll for jobs
  config.scheduler_interval = 5.seconds       # How often scheduler promotes delayed jobs
  config.is_auto_start_enabled = true         # Auto-start when Amber server starts
end
```

Or through `Amber::Server.configure`:

```crystal
Amber::Server.configure do |app|
  app.jobs.adapter = :memory
  app.jobs.queues = ["default", "critical", "low"]
  app.jobs.workers = 2
  app.jobs.work_stealing_enabled = true
  app.jobs.polling_interval = 1.second
end
```

### YAML Configuration (JobsConfig)

The `Amber::Configuration::JobsConfig` class supports YAML-based configuration:

```yaml
jobs:
  adapter: memory
  queues:
    - default
    - critical
    - low
  workers: 2
  work_stealing: false
  polling_interval_seconds: 1.0
  scheduler_interval_seconds: 5.0
  auto_start: false
```

| YAML Key | Type | Default | Description |
|---|---|---|---|
| `adapter` | `String` | `"memory"` | Queue adapter name |
| `queues` | `Array(String)` | `["default"]` | Queue names in priority order |
| `workers` | `Int32` | `1` | Number of worker fibers |
| `work_stealing` | `Bool` | `false` | Enable work-stealing from idle web instances |
| `polling_interval_seconds` | `Float64` | `1.0` | Worker poll frequency in seconds |
| `scheduler_interval_seconds` | `Float64` | `5.0` | Scheduler check frequency in seconds |
| `auto_start` | `Bool` | `false` | Auto-start workers with the Amber server |

`JobsConfig` includes validation via `validate!` that enforces `workers >= 1` and positive interval values.

### Configuration Properties (Amber::Jobs::Configuration)

| Property | Type | Default | Description |
|---|---|---|---|
| `adapter` | `Symbol` | `:memory` | Queue adapter type |
| `list_of_queues` | `Array(String)` | `["default"]` | Queues in priority order |
| `number_of_workers` | `Int32` | `1` | Worker fiber count |
| `is_work_stealing_enabled?` | `Bool` | `false` | Work-stealing toggle |
| `polling_interval` | `Time::Span` | `1.second` | Worker polling frequency |
| `scheduler_interval` | `Time::Span` | `5.seconds` | Scheduler check frequency |
| `is_auto_start_enabled?` | `Bool` | `false` | Auto-start on server boot |

## Queue Adapters

### MemoryQueueAdapter (Built-in)

The default adapter stores jobs in Mutex-protected in-memory data structures. Suitable for development, testing, and single-instance applications.

Characteristics:
- Thread-safe via `Mutex` for concurrent fiber access
- Delayed jobs stored in a sorted array and promoted during `dequeue`
- Jobs are lost on application restart (no persistence)
- Tracks completed, failed, and dead jobs for inspection

```crystal
# Explicitly set (this is also the default)
Amber::Jobs.adapter = Amber::Jobs::MemoryQueueAdapter.new
```

The memory adapter provides additional inspection methods beyond the base `QueueAdapter` interface:

```crystal
adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
adapter.size("default")       # Pending jobs in "default" queue
adapter.scheduled_size         # Delayed jobs waiting for their scheduled time
adapter.completed_size         # Successfully completed jobs
adapter.failed_size            # Jobs that failed but may retry
adapter.dead_size              # Jobs that exceeded max retries
adapter.all_jobs               # All tracked job envelopes
adapter.dead_jobs              # Dead job envelopes only
```

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
    json = @redis.rpop("queue:#{queue}")
    return nil unless json
    JobEnvelope.from_json(json.as(String))
  end

  def schedule(envelope : JobEnvelope, at : Time) : Nil
    envelope.scheduled_at = at
    @redis.zadd("scheduled_jobs", at.to_unix_f, envelope.to_json)
  end

  def size(queue : String) : Int32
    @redis.llen("queue:#{queue}").to_i32
  end

  def clear(queue : String) : Nil
    @redis.del("queue:#{queue}")
  end

  def mark_completed(id : String) : Nil
    @redis.hset("completed_jobs", id, Time.utc.to_s)
  end

  def mark_failed(id : String, error : String) : Nil
    @redis.hset("failed_jobs", id, error)
  end

  def retry_failed(id : String) : Nil
    json = @redis.hget("failed_jobs", id)
    return unless json
    @redis.hdel("failed_jobs", id)
    envelope = JobEnvelope.from_json(json.as(String))
    envelope.status = JobEnvelope::Status::Pending
    enqueue(envelope)
  end

  def dead_jobs : Array(JobEnvelope)
    # Implementation depends on your Redis data model
    Array(JobEnvelope).new
  end

  def all_jobs : Array(JobEnvelope)
    # Implementation depends on your Redis data model
    Array(JobEnvelope).new
  end

  def close : Nil
    @redis.close
  end

  def healthy? : Bool
    @redis.ping == "PONG"
  end
end
```

Set the custom adapter before starting jobs:

```crystal
Amber::Jobs.adapter = RedisQueueAdapter.new(Redis::Client.new)
```

### QueueAdapter Abstract Interface

| Method | Signature | Description |
|---|---|---|
| `enqueue` | `(envelope : JobEnvelope) : Nil` | Add job to queue |
| `dequeue` | `(queue : String) : JobEnvelope?` | Remove and return next ready job |
| `schedule` | `(envelope : JobEnvelope, at : Time) : Nil` | Schedule for future execution |
| `size` | `(queue : String) : Int32` | Count pending jobs in queue |
| `clear` | `(queue : String) : Nil` | Remove all jobs from queue |
| `mark_completed` | `(id : String) : Nil` | Mark job as completed |
| `mark_failed` | `(id : String, error : String) : Nil` | Mark job as failed |
| `retry_failed` | `(id : String) : Nil` | Re-enqueue a failed job |
| `dead_jobs` | `: Array(JobEnvelope)` | Return all dead jobs |
| `all_jobs` | `: Array(JobEnvelope)` | Return all tracked jobs |
| `close` | `: Nil` | Cleanup (default no-op) |
| `healthy?` | `: Bool` | Health check (default `true`) |

## Worker

The `Amber::Jobs::Worker` class runs in a background fiber, polling configured queues in priority order. When a job is found, it deserializes and executes it.

Queue priority: workers iterate `list_of_queues` in order and execute the first available job. Place higher-priority queues first:

```crystal
config.queues = ["critical", "default", "low"]
```

Workers track their processed count via `jobs_processed`:

```crystal
worker = Amber::Jobs::Worker.new(
  adapter: Amber::Jobs.adapter,
  list_of_queues: ["default"],
  polling_interval: 1.second,
)
worker.start
# ... later
Log.info { "Worker processed #{worker.jobs_processed} jobs" }
worker.stop
```

## Starting and Stopping

### Auto-start with the server

Set `is_auto_start_enabled` to `true` in configuration and the jobs system starts when `Amber::Server` starts:

```crystal
Amber::Jobs.configure do |config|
  config.is_auto_start_enabled = true
end
```

### Manual start

```crystal
# Register all job classes first
Amber::Jobs.register(SendWelcomeEmail)
Amber::Jobs.register(ImportCsvData)
Amber::Jobs.register(CleanupExpiredSessions)

# Start workers and scheduler
Amber::Jobs.start

# Stop everything gracefully
Amber::Jobs.stop
```

`Amber::Jobs.start` spawns the configured number of workers, an optional work-stealing worker, and the scheduler. `Amber::Jobs.stop` stops all workers and the scheduler.

### Reset (testing)

```crystal
Amber::Jobs.reset  # Stops workers, clears adapter and configuration, empties job registry
```

## Scheduler

The `Amber::Jobs::Scheduler` runs in a background fiber at `scheduler_interval` (default 5 seconds). Its purpose is to promote delayed/scheduled jobs that have reached their `scheduled_at` time into the immediate queue. For the `MemoryQueueAdapter`, promotion also happens during `dequeue`, so the scheduler serves as a safety net when no dequeue calls are happening.

## Example Patterns

### Email delivery

```crystal
class DeliverEmail < Amber::Jobs::Job
  include JSON::Serializable

  property to : String
  property subject : String
  property body : String

  def initialize(@to : String, @subject : String, @body : String)
  end

  def perform
    Amber::Mailer::Client.deliver(to: to, subject: subject, body: body)
  end

  def self.queue : String
    "mailers"
  end

  def self.max_retries : Int32
    5
  end
end

Amber::Jobs.register(DeliverEmail)

# In a controller
DeliverEmail.new(
  to: "user@example.com",
  subject: "Welcome!",
  body: "<h1>Hello</h1>"
).enqueue
```

### Periodic cleanup

```crystal
class CleanupExpiredSessions < Amber::Jobs::Job
  include JSON::Serializable

  def initialize
  end

  def perform
    # Delete sessions older than 30 days
    expired_count = SessionStore.delete_expired(30.days.ago)
    Log.info { "Cleaned up #{expired_count} expired sessions" }
  end

  def self.queue : String
    "maintenance"
  end
end

Amber::Jobs.register(CleanupExpiredSessions)

# Enqueue from a scheduled task or controller
CleanupExpiredSessions.new.enqueue
```

### Data import with custom retry backoff

```crystal
class ProcessUpload < Amber::Jobs::Job
  include JSON::Serializable

  property upload_id : Int64
  property file_path : String

  def initialize(@upload_id : Int64, @file_path : String)
  end

  def perform
    upload = Upload.find(upload_id)
    upload.process_file(file_path)
    upload.update(status: "completed")
  rescue ex
    Upload.find(upload_id).update(status: "failed", error: ex.message)
    raise ex  # Re-raise so the retry system handles it
  end

  def self.queue : String
    "imports"
  end

  def self.max_retries : Int32
    5
  end

  # Linear 60-second backoff
  def self.retry_backoff(attempt : Int32) : Time::Span
    (60 * attempt).seconds
  end
end

Amber::Jobs.register(ProcessUpload)
```

## Key Source Files

| File | Contains |
|---|---|
| `src/amber/jobs.cr` | `Amber::Jobs` module -- registry, adapter management, start/stop |
| `src/amber/jobs/job.cr` | `Amber::Jobs::Job` -- abstract base class for all jobs |
| `src/amber/jobs/job_envelope.cr` | `Amber::Jobs::JobEnvelope` -- metadata wrapper with status lifecycle |
| `src/amber/jobs/queue_adapter.cr` | `Amber::Jobs::QueueAdapter` -- abstract adapter interface |
| `src/amber/jobs/memory_queue_adapter.cr` | `Amber::Jobs::MemoryQueueAdapter` -- in-memory adapter |
| `src/amber/jobs/configuration.cr` | `Amber::Jobs::Configuration` -- runtime configuration class |
| `src/amber/jobs/worker.cr` | `Amber::Jobs::Worker` -- job execution and retry handling |
| `src/amber/jobs/scheduler.cr` | `Amber::Jobs::Scheduler` -- delayed job promotion |
| `src/amber/configuration/jobs_config.cr` | `Amber::Configuration::JobsConfig` -- YAML-based configuration |
