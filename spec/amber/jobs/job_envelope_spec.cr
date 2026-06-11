require "../../spec_helper"

describe Amber::Jobs::JobEnvelope do
  describe "#initialize" do
    it "creates an envelope with default values" do
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: %({"name":"test"})
      )

      envelope.id.should_not be_empty
      envelope.job_class.should eq("TestJob")
      envelope.payload.should eq(%({"name":"test"}))
      envelope.queue.should eq("default")
      envelope.attempts.should eq(0)
      envelope.max_retries.should eq(3)
      envelope.status.should eq(Amber::Jobs::JobEnvelope::Status::Pending)
      envelope.last_error.should be_nil
      envelope.created_at.should be_close(Time.utc, 1.second)
      envelope.scheduled_at.should be_close(Time.utc, 1.second)
    end

    it "creates an envelope with custom values" do
      scheduled = Time.utc + 10.minutes

      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "CriticalJob",
        payload: "{}",
        queue: "critical",
        max_retries: 5,
        scheduled_at: scheduled
      )

      envelope.queue.should eq("critical")
      envelope.max_retries.should eq(5)
      envelope.scheduled_at.should eq(scheduled)
    end

    it "generates a unique UUID for each envelope" do
      envelope_a = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      envelope_b = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")

      envelope_a.id.should_not eq(envelope_b.id)
    end
  end

  describe "#is_ready_to_run?" do
    it "returns true when status is pending and scheduled time has passed" do
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        scheduled_at: Time.utc - 1.second
      )

      envelope.is_ready_to_run?.should be_true
    end

    it "returns false when scheduled time is in the future" do
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        scheduled_at: Time.utc + 1.hour
      )

      envelope.is_ready_to_run?.should be_false
    end

    it "returns false when status is not pending" do
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      envelope.mark_as_running

      envelope.is_ready_to_run?.should be_false
    end
  end

  describe "#has_exceeded_max_retries?" do
    it "returns false when attempts are below max retries" do
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        max_retries: 3
      )

      envelope.has_exceeded_max_retries?.should be_false
    end

    it "returns true when attempts equal max retries" do
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        max_retries: 3
      )

      3.times { envelope.mark_as_running }
      envelope.has_exceeded_max_retries?.should be_true
    end

    it "returns true when attempts exceed max retries" do
      envelope = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: "{}",
        max_retries: 2
      )

      3.times { envelope.mark_as_running }
      envelope.has_exceeded_max_retries?.should be_true
    end
  end

  describe "#mark_as_running" do
    it "increments attempts and sets status to Running" do
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")

      envelope.mark_as_running
      envelope.attempts.should eq(1)
      envelope.status.should eq(Amber::Jobs::JobEnvelope::Status::Running)

      # Calling again increments further
      envelope.status = Amber::Jobs::JobEnvelope::Status::Pending
      envelope.mark_as_running
      envelope.attempts.should eq(2)
    end
  end

  describe "#mark_as_completed" do
    it "sets status to Completed" do
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      envelope.mark_as_running
      envelope.mark_as_completed

      envelope.status.should eq(Amber::Jobs::JobEnvelope::Status::Completed)
    end
  end

  describe "#mark_as_failed" do
    it "sets status to Failed and records the error" do
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      envelope.mark_as_running
      envelope.mark_as_failed("Connection timeout")

      envelope.status.should eq(Amber::Jobs::JobEnvelope::Status::Failed)
      envelope.last_error.should eq("Connection timeout")
    end
  end

  describe "#mark_as_dead" do
    it "sets status to Dead and records the error" do
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      envelope.mark_as_dead("Max retries exceeded")

      envelope.status.should eq(Amber::Jobs::JobEnvelope::Status::Dead)
      envelope.last_error.should eq("Max retries exceeded")
    end
  end

  describe "#schedule_retry" do
    it "sets status to Pending and updates scheduled_at with backoff" do
      envelope = Amber::Jobs::JobEnvelope.new(job_class: "TestJob", payload: "{}")
      envelope.mark_as_running
      envelope.mark_as_failed("Error")

      before_retry = Time.utc
      envelope.schedule_retry(30.seconds)

      envelope.status.should eq(Amber::Jobs::JobEnvelope::Status::Pending)
      envelope.scheduled_at.should be_close(before_retry + 30.seconds, 1.second)
    end
  end

  describe "JSON serialization" do
    it "serializes and deserializes an envelope" do
      original = Amber::Jobs::JobEnvelope.new(
        job_class: "TestJob",
        payload: %({"user_id":42}),
        queue: "critical",
        max_retries: 5
      )

      json = original.to_json
      restored = Amber::Jobs::JobEnvelope.from_json(json)

      restored.id.should eq(original.id)
      restored.job_class.should eq(original.job_class)
      restored.payload.should eq(original.payload)
      restored.queue.should eq(original.queue)
      restored.max_retries.should eq(original.max_retries)
      restored.status.should eq(original.status)
    end
  end
end
