require "../../spec_helper"

# Test job for DSL specs
class DslTestJob < Amber::Jobs::Job
  include JSON::Serializable

  property user_id : Int64

  def initialize(@user_id : Int64)
  end

  def perform
  end

  def self.queue : String
    "mailers"
  end

  def self.max_retries : Int32
    5
  end
end

Amber::Jobs.register(DslTestJob)

describe "Amber::Jobs DSL" do
  before_each do
    Amber::Jobs.adapter = Amber::Jobs::MemoryQueueAdapter.new
  end

  describe "Job#enqueue" do
    it "enqueues immediately by default" do
      envelope = DslTestJob.new(user_id: 42_i64).enqueue

      envelope.queue.should eq("mailers")
      envelope.max_retries.should eq(5)
      envelope.scheduled_at.should be_close(Time.utc, 1.second)

      adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
      adapter.size("mailers").should eq(1)
    end

    it "enqueues with a delay" do
      before = Time.utc
      envelope = DslTestJob.new(user_id: 42_i64).enqueue(delay: 5.minutes)

      envelope.scheduled_at.should be_close(before + 5.minutes, 1.second)

      adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
      adapter.size("mailers").should eq(0)
      adapter.scheduled_size.should eq(1)
    end

    it "enqueues to a specific queue override" do
      envelope = DslTestJob.new(user_id: 42_i64).enqueue(queue: "critical")

      envelope.queue.should eq("critical")

      adapter = Amber::Jobs.adapter.as(Amber::Jobs::MemoryQueueAdapter)
      adapter.size("critical").should eq(1)
      adapter.size("mailers").should eq(0)
    end

    it "enqueues with both queue override and delay" do
      before = Time.utc
      envelope = DslTestJob.new(user_id: 42_i64).enqueue(
        queue: "low",
        delay: 1.hour
      )

      envelope.queue.should eq("low")
      envelope.scheduled_at.should be_close(before + 1.hour, 1.second)
    end

    it "preserves job payload through serialization" do
      envelope = DslTestJob.new(user_id: 99_i64).enqueue

      payload = JSON.parse(envelope.payload)
      payload["user_id"].as_i64.should eq(99_i64)
    end
  end

  describe "Amber::Jobs.register and .deserialize" do
    it "deserializes a registered job from its envelope" do
      original = DslTestJob.new(user_id: 77_i64)
      envelope = original.enqueue

      job = Amber::Jobs.deserialize(envelope.job_class, envelope.payload)
      job.should_not be_nil
      job.should be_a(DslTestJob)

      deserialized = job.as(DslTestJob)
      deserialized.user_id.should eq(77_i64)
    end

    it "returns nil for unregistered job classes" do
      job = Amber::Jobs.deserialize("UnknownJob", "{}")
      job.should be_nil
    end
  end
end
