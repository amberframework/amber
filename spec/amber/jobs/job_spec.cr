require "../../spec_helper"

# Test job classes for spec purposes

class SimpleTestJob < Amber::Jobs::Job
  include JSON::Serializable

  property name : String

  def initialize(@name : String)
  end

  def perform
    # No-op for testing
  end
end

class CustomQueueJob < Amber::Jobs::Job
  include JSON::Serializable

  def initialize
  end

  def perform
  end

  def self.queue : String
    "critical"
  end
end

class CustomRetryJob < Amber::Jobs::Job
  include JSON::Serializable

  def initialize
  end

  def perform
  end

  def self.max_retries : Int32
    5
  end

  def self.retry_backoff(attempt : Int32) : Time::Span
    (attempt * 10).seconds
  end
end

# Register test jobs
Amber::Jobs.register(SimpleTestJob)
Amber::Jobs.register(CustomQueueJob)
Amber::Jobs.register(CustomRetryJob)

describe Amber::Jobs::Job do
  before_each do
    adapter = Amber::Jobs::MemoryQueueAdapter.new
    Amber::Jobs.adapter = adapter
  end

  describe ".queue" do
    it "defaults to 'default'" do
      SimpleTestJob.queue.should eq("default")
    end

    it "can be overridden by subclasses" do
      CustomQueueJob.queue.should eq("critical")
    end
  end

  describe ".max_retries" do
    it "defaults to 3" do
      SimpleTestJob.max_retries.should eq(3)
    end

    it "can be overridden by subclasses" do
      CustomRetryJob.max_retries.should eq(5)
    end
  end

  describe ".retry_backoff" do
    it "uses exponential backoff by default" do
      SimpleTestJob.retry_backoff(1).should eq(2.seconds)
      SimpleTestJob.retry_backoff(2).should eq(4.seconds)
      SimpleTestJob.retry_backoff(3).should eq(8.seconds)
    end

    it "can be overridden by subclasses" do
      CustomRetryJob.retry_backoff(1).should eq(10.seconds)
      CustomRetryJob.retry_backoff(2).should eq(20.seconds)
      CustomRetryJob.retry_backoff(3).should eq(30.seconds)
    end
  end

  describe "#enqueue" do
    it "enqueues the job to the default queue" do
      job = SimpleTestJob.new(name: "test")
      envelope = job.enqueue

      envelope.job_class.should eq("SimpleTestJob")
      envelope.queue.should eq("default")
      envelope.status.should eq(Amber::Jobs::JobEnvelope::Status::Pending)
      envelope.max_retries.should eq(3)

      adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
      adapter.size("default").should eq(1)
    end

    it "enqueues to the class-defined queue" do
      job = CustomQueueJob.new
      envelope = job.enqueue

      envelope.queue.should eq("critical")

      adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
      adapter.size("critical").should eq(1)
    end

    it "allows overriding the queue at enqueue time" do
      job = SimpleTestJob.new(name: "test")
      envelope = job.enqueue(queue: "high_priority")

      envelope.queue.should eq("high_priority")

      adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
      adapter.size("high_priority").should eq(1)
    end

    it "allows setting a delay" do
      job = SimpleTestJob.new(name: "test")
      before = Time.utc
      envelope = job.enqueue(delay: 5.minutes)

      envelope.scheduled_at.should be_close(before + 5.minutes, 1.second)

      # Should be in the scheduled set, not the immediate queue
      adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
      adapter.size("default").should eq(0)
      adapter.scheduled_size.should eq(1)
    end

    it "serializes job data as JSON payload" do
      job = SimpleTestJob.new(name: "hello_world")
      envelope = job.enqueue

      payload = JSON.parse(envelope.payload)
      payload["name"].as_s.should eq("hello_world")
    end
  end
end
