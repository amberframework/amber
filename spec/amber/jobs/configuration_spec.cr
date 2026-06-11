require "../../spec_helper"

describe Amber::Jobs::Configuration do
  describe "#initialize" do
    it "sets sensible defaults" do
      config = Amber::Jobs::Configuration.new

      config.adapter.should eq(:memory)
      config.list_of_queues.should eq(["default"])
      config.number_of_workers.should eq(1)
      config.is_work_stealing_enabled?.should be_false
      config.polling_interval.should eq(1.second)
      config.scheduler_interval.should eq(5.seconds)
      config.is_auto_start_enabled?.should be_false
    end
  end

  describe "property setters" do
    it "configures adapter" do
      config = Amber::Jobs::Configuration.new
      config.adapter = :redis
      config.adapter.should eq(:redis)
    end

    it "configures queues" do
      config = Amber::Jobs::Configuration.new
      config.queues = ["default", "critical", "low"]
      config.queues.should eq(["default", "critical", "low"])
      config.list_of_queues.should eq(["default", "critical", "low"])
    end

    it "configures workers count" do
      config = Amber::Jobs::Configuration.new
      config.workers = 4
      config.workers.should eq(4)
      config.number_of_workers.should eq(4)
    end

    it "configures work stealing" do
      config = Amber::Jobs::Configuration.new
      config.work_stealing_enabled = true
      config.work_stealing_enabled?.should be_true
      config.is_work_stealing_enabled?.should be_true
    end

    it "configures polling interval" do
      config = Amber::Jobs::Configuration.new
      config.polling_interval = 500.milliseconds
      config.polling_interval.should eq(500.milliseconds)
    end

    it "configures scheduler interval" do
      config = Amber::Jobs::Configuration.new
      config.scheduler_interval = 10.seconds
      config.scheduler_interval.should eq(10.seconds)
    end

    it "configures auto start" do
      config = Amber::Jobs::Configuration.new
      config.is_auto_start_enabled = true
      config.is_auto_start_enabled?.should be_true
    end
  end
end
