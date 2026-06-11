require "../../spec_helper"

describe Amber::Jobs::Scheduler do
  describe "#initialize" do
    it "creates a scheduler with default interval" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      scheduler = Amber::Jobs::Scheduler.new(adapter: adapter)

      scheduler.adapter.should eq(adapter)
      scheduler.interval.should eq(5.seconds)
      scheduler.is_running?.should be_false
    end

    it "creates a scheduler with custom interval" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      scheduler = Amber::Jobs::Scheduler.new(adapter: adapter, interval: 10.seconds)

      scheduler.interval.should eq(10.seconds)
    end
  end

  describe "#start and #stop" do
    it "starts and stops the scheduler" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      scheduler = Amber::Jobs::Scheduler.new(
        adapter: adapter,
        interval: 50.milliseconds
      )

      scheduler.is_running?.should be_false
      scheduler.start
      scheduler.is_running?.should be_true

      scheduler.stop
      # Give the fiber time to check the flag
      sleep 100.milliseconds
      scheduler.is_running?.should be_false
    end

    it "does not start twice" do
      adapter = Amber::Jobs::MemoryQueueAdapter.new
      scheduler = Amber::Jobs::Scheduler.new(
        adapter: adapter,
        interval: 50.milliseconds
      )

      scheduler.start
      scheduler.start # Should be a no-op
      scheduler.is_running?.should be_true

      scheduler.stop
    end
  end
end
