require "../../spec_helper"

describe Amber::Jobs::MemoryQueueAdapter do
  describe "#enqueue and #dequeue" do
    it "enqueues and dequeues a job from the default queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        queue: "default"
      )

      adapter.enqueue(envelope)
      adapter.size("default").should eq(1)

      dequeued = adapter.dequeue("default")
      dequeued.should_not be_nil
      dequeued.not_nil!.id.should eq(envelope.id)
      adapter.size("default").should eq(0)
    end

    it "returns nil when dequeuing from an empty queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      adapter.dequeue("default").should be_nil
    end

    it "returns nil when dequeuing from a non-existent queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      adapter.dequeue("non_existent").should be_nil
    end

    it "dequeues in FIFO order" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      envelope_a = Amber::Jobs::JobEnvelope.new(job_class: "JobA", payload: "{}")
      envelope_b = Amber::Jobs::JobEnvelope.new(job_class: "JobB", payload: "{}")
      envelope_c = Amber::Jobs::JobEnvelope.new(job_class: "JobC", payload: "{}")

      adapter.enqueue(envelope_a)
      adapter.enqueue(envelope_b)
      adapter.enqueue(envelope_c)

      adapter.dequeue("default").not_nil!.id.should eq(envelope_a.id)
      adapter.dequeue("default").not_nil!.id.should eq(envelope_b.id)
      adapter.dequeue("default").not_nil!.id.should eq(envelope_c.id)
    end
  end

  describe "multiple queues" do
    it "keeps queues separate" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      default_job = Amber::Jobs::JobEnvelope.new(job_class: "DefaultJob", payload: "{}", queue: "default")
      critical_job = Amber::Jobs::JobEnvelope.new(job_class: "CriticalJob", payload: "{}", queue: "critical")

      adapter.enqueue(default_job)
      adapter.enqueue(critical_job)

      adapter.size("default").should eq(1)
      adapter.size("critical").should eq(1)

      dequeued_critical = adapter.dequeue("critical")
      dequeued_critical.not_nil!.job_class.should eq("CriticalJob")

      dequeued_default = adapter.dequeue("default")
      dequeued_default.not_nil!.job_class.should eq("DefaultJob")
    end
  end

  describe "#schedule" do
    it "schedules a job for future execution" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      future_time = Time.utc + 1.hour

      adapter.schedule(envelope, at: future_time)

      # Should not be available in the immediate queue
      adapter.dequeue("default").should be_nil
      adapter.scheduled_size.should eq(1)
    end

    it "promotes scheduled jobs when their time arrives" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")

      # Schedule in the past so it will be immediately promoted
      past_time = Time.utc - 1.second
      adapter.schedule(envelope, at: past_time)

      # Dequeue triggers promotion
      dequeued = adapter.dequeue("default")
      dequeued.should_not be_nil
      dequeued.not_nil!.id.should eq(envelope.id)
    end
  end

  describe "delayed enqueue" do
    it "places future-scheduled envelopes in the scheduled set" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      future_time = Time.utc + 30.minutes
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        scheduled_at: future_time
      )

      adapter.enqueue(envelope)

      adapter.size("default").should eq(0)
      adapter.scheduled_size.should eq(1)
    end

    it "places past-scheduled envelopes directly in the queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        scheduled_at: Time.utc - 1.second
      )

      adapter.enqueue(envelope)

      adapter.size("default").should eq(1)
      adapter.scheduled_size.should eq(0)
    end
  end

  describe "#size" do
    it "returns the number of pending jobs in a queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      adapter.size("default").should eq(0)

      3.times do |i|
        adapter.enqueue(Amber::Jobs::JobEnvelope.new(job_class: "Job#{i}", payload: "{}"))
      end

      adapter.size("default").should eq(3)
    end

    it "returns 0 for non-existent queues" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      adapter.size("non_existent").should eq(0)
    end
  end

  describe "#clear" do
    it "removes all jobs from a queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      3.times do |i|
        adapter.enqueue(Amber::Jobs::JobEnvelope.new(job_class: "Job#{i}", payload: "{}"))
      end

      adapter.size("default").should eq(3)
      adapter.clear("default")
      adapter.size("default").should eq(0)
    end

    it "also clears scheduled jobs for the queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        scheduled_at: Time.utc + 1.hour
      )

      adapter.enqueue(envelope)
      adapter.scheduled_size.should eq(1)

      adapter.clear("default")
      adapter.scheduled_size.should eq(0)
    end

    it "does not affect other queues" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      adapter.enqueue(Amber::Jobs::JobEnvelope.new(job_class: "DefaultJob", payload: "{}", queue: "default"))
      adapter.enqueue(Amber::Jobs::JobEnvelope.new(job_class: "CriticalJob", payload: "{}", queue: "critical"))

      adapter.clear("default")

      adapter.size("default").should eq(0)
      adapter.size("critical").should eq(1)
    end
  end

  describe "#mark_completed" do
    it "marks a job as completed" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      adapter.enqueue(envelope)
      adapter.dequeue("default")

      adapter.mark_completed(envelope.id)
      adapter.completed_size.should eq(1)
    end
  end

  describe "#mark_failed" do
    it "marks a job as failed with an error message" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      adapter.enqueue(envelope)
      adapter.dequeue("default")

      adapter.mark_failed(envelope.id, "Something went wrong")
      adapter.failed_size.should eq(1)
    end
  end

  describe "#retry_failed" do
    it "re-enqueues a failed job" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      adapter.enqueue(envelope)
      adapter.dequeue("default")

      adapter.mark_failed(envelope.id, "Timeout")
      adapter.failed_size.should eq(1)
      adapter.size("default").should eq(0)

      adapter.retry_failed(envelope.id)
      adapter.failed_size.should eq(0)
      adapter.size("default").should eq(1)
    end

    it "is a no-op for non-existent job IDs" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      # Should not raise
      adapter.retry_failed("non_existent_id")
    end
  end

  describe "#mark_dead and #dead_jobs" do
    it "marks a job as dead and includes it in dead_jobs" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      adapter.enqueue(envelope)
      adapter.dequeue("default")

      adapter.mark_dead(envelope.id, "Max retries exceeded")
      adapter.dead_size.should eq(1)

      dead = adapter.dead_jobs
      dead.size.should eq(1)
      dead.first.id.should eq(envelope.id)
      dead.first.status.should eq(Amber::Jobs::JobEnvelope::Status::Dead)
    end
  end

  describe "#all_jobs" do
    it "returns all tracked job envelopes" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      3.times do |i|
        adapter.enqueue(Amber::Jobs::JobEnvelope.new(job_class: "Job#{i}", payload: "{}"))
      end

      adapter.all_jobs.size.should eq(3)
    end
  end

  describe "#close" do
    it "clears all data" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new

      adapter.enqueue(Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}"))
      adapter.all_jobs.size.should eq(1)

      adapter.close
      adapter.all_jobs.size.should eq(0)
      adapter.size("default").should eq(0)
    end
  end

  describe "thread safety" do
    it "handles concurrent enqueue and dequeue from multiple fibers" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      channel = Channel(Nil).new
      job_count = 100

      # Enqueue from multiple fibers concurrently
      job_count.times do |i|
        spawn do
          adapter.enqueue(Amber::Jobs::JobEnvelope.new(
            job_class: "ConcurrentJob#{i}",
            payload: "{}",
            queue: "default"
          ))
          channel.send(nil)
        end
      end

      job_count.times { channel.receive }

      adapter.size("default").should eq(job_count)

      # Dequeue from multiple fibers concurrently
      dequeued_count = Atomic(Int32).new(0)
      job_count.times do
        spawn do
          if adapter.dequeue("default")
            dequeued_count.add(1)
          end
          channel.send(nil)
        end
      end

      job_count.times { channel.receive }

      dequeued_count.get.should eq(job_count)
      adapter.size("default").should eq(0)
    end
  end
end
