require "../../spec_helper"

# Test job that tracks execution for worker specs
class WorkerTestJob < Amber::Jobs::Job
  include JSON::Serializable

  property value : String

  # Class-level tracking of executed jobs
  @@list_of_executed_values = [] of String
  @@execution_mutex = Mutex.new

  def initialize(@value : String)
  end

  def perform
    @@execution_mutex.synchronize do
      @@list_of_executed_values << @value
    end
  end

  def self.list_of_executed_values : Array(String)
    @@execution_mutex.synchronize do
      @@list_of_executed_values.dup
    end
  end

  def self.clear_executed_values
    @@execution_mutex.synchronize do
      @@list_of_executed_values.clear
    end
  end
end

# Test job that always fails
class FailingTestJob < Amber::Jobs::Job
  include JSON::Serializable

  property error_message : String

  def initialize(@error_message : String)
  end

  def perform
    raise @error_message
  end

  def self.max_retries : Int32
    2
  end
end

Amber::Jobs.register(WorkerTestJob)
Amber::Jobs.register(FailingTestJob)

describe Amber::Jobs::Worker do
  before_each do
    WorkerTestJob.clear_executed_values
  end

  describe "#process_next_job" do
    it "processes a job from the queue" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      Amber::Jobs.adapter = adapter
      worker = Amber::Jobs::Worker.new(adapter: adapter)

      WorkerTestJob.new(value: "hello").enqueue
      result = worker.process_next_job

      result.should be_true

      # Give the job a moment to be processed (it runs synchronously in process_next_job)
      WorkerTestJob.list_of_executed_values.should contain("hello")
    end

    it "returns false when no jobs are available" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      worker = Amber::Jobs::Worker.new(adapter: adapter)

      result = worker.process_next_job
      result.should be_false
    end

    it "processes jobs from multiple queues in order" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      Amber::Jobs.adapter = adapter
      worker = Amber::Jobs::Worker.new(
        adapter: adapter,
        list_of_queues: ["critical", "default"]
      )

      # Enqueue to default first, then critical
      WorkerTestJob.new(value: "default_job").enqueue(queue: "default")
      WorkerTestJob.new(value: "critical_job").enqueue(queue: "critical")

      # Should process critical first because it is listed first
      worker.process_next_job
      WorkerTestJob.list_of_executed_values.should eq(["critical_job"])

      worker.process_next_job
      WorkerTestJob.list_of_executed_values.should eq(["critical_job", "default_job"])
    end

    it "marks completed jobs" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      Amber::Jobs.adapter = adapter
      worker = Amber::Jobs::Worker.new(adapter: adapter)

      WorkerTestJob.new(value: "complete_me").enqueue
      worker.process_next_job

      adapter.completed_size.should eq(1)
    end

    it "increments jobs_processed counter" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      Amber::Jobs.adapter = adapter
      worker = Amber::Jobs::Worker.new(adapter: adapter)

      worker.jobs_processed.should eq(0)

      WorkerTestJob.new(value: "job1").enqueue
      worker.process_next_job
      worker.jobs_processed.should eq(1)

      WorkerTestJob.new(value: "job2").enqueue
      worker.process_next_job
      worker.jobs_processed.should eq(2)
    end
  end

  describe "failure handling" do
    it "re-enqueues failed jobs with backoff when retries remain" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      Amber::Jobs.adapter = adapter
      worker = Amber::Jobs::Worker.new(adapter: adapter)

      FailingTestJob.new(error_message: "boom").enqueue
      worker.process_next_job

      # Job should have been re-enqueued as scheduled (future time)
      adapter.size("default").should eq(0)
      adapter.scheduled_size.should eq(1)
    end

    it "marks jobs as dead when max retries are exceeded" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      Amber::Jobs.adapter = adapter
      worker = Amber::Jobs::Worker.new(adapter: adapter)

      # Create an envelope that has already been retried max times
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "FailingTestJob",
        payload: %({"error_message":"final_failure"}),
        max_retries: 2
      )
      # Simulate previous attempts
      envelope.mark_as_running # attempt 1
      envelope.status = Amber::Jobs::JobEnvelope::Status::Pending
      envelope.mark_as_running # attempt 2
      envelope.status = Amber::Jobs::JobEnvelope::Status::Pending

      adapter.enqueue(envelope)
      worker.process_next_job

      # Job should be dead now (3 attempts >= 2 max_retries)
      adapter.dead_size.should eq(1)
    end
  end

  describe "work stealing mode" do
    it "skips processing when idle_only is true and requests are pending" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      Amber::Jobs.adapter = adapter
      worker = Amber::Jobs::Worker.new(
        adapter: adapter,
        idle_only: true
      )

      WorkerTestJob.new(value: "stolen").enqueue

      # Simulate pending HTTP requests
      Amber::Jobs::Worker.pending_request_mutex.synchronize do
        Amber::Jobs::Worker.pending_request_count = 5_i64
      end

      result = worker.process_next_job
      result.should be_false
      WorkerTestJob.list_of_executed_values.should be_empty

      # Reset pending count
      Amber::Jobs::Worker.pending_request_mutex.synchronize do
        Amber::Jobs::Worker.pending_request_count = 0_i64
      end

      result = worker.process_next_job
      result.should be_true
      WorkerTestJob.list_of_executed_values.should contain("stolen")
    end
  end

  describe "#start and #stop" do
    it "starts and stops the worker" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      worker = Amber::Jobs::Worker.new(
        adapter: adapter,
        polling_interval: 50.milliseconds
      )

      worker.is_running?.should be_false
      worker.start
      worker.is_running?.should be_true

      worker.stop
      worker.is_running?.should be_false
    end
  end
end
