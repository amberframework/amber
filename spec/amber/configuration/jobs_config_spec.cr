require "../../spec_helper"

module Amber::Configuration
  describe JobsConfig do
    describe "defaults" do
      it "has sensible default values" do
        config = JobsConfig.new
        config.adapter.should eq "memory"
        config.queues.should eq ["default"]
        config.workers.should eq 1
        config.work_stealing.should be_false
        config.polling_interval_seconds.should eq 1.0
        config.scheduler_interval_seconds.should eq 5.0
        config.auto_start.should be_false
      end
    end

    describe "YAML deserialization" do
      it "deserializes from YAML" do
        yaml = <<-YAML
        adapter: "memory"
        queues:
          - default
          - critical
          - low
        workers: 4
        work_stealing: true
        polling_interval_seconds: 0.5
        scheduler_interval_seconds: 10.0
        auto_start: true
        YAML

        config = JobsConfig.from_yaml(yaml)
        config.adapter.should eq "memory"
        config.queues.should eq ["default", "critical", "low"]
        config.workers.should eq 4
        config.work_stealing.should be_true
        config.polling_interval_seconds.should eq 0.5
        config.scheduler_interval_seconds.should eq 10.0
        config.auto_start.should be_true
      end
    end

    describe "#adapter_symbol" do
      it "returns :memory for memory adapter" do
        config = JobsConfig.new
        config.adapter = "memory"
        config.adapter_symbol.should eq :memory
      end
    end

    describe "#polling_interval" do
      it "returns Time::Span from seconds" do
        config = JobsConfig.new
        config.polling_interval_seconds = 2.5
        config.polling_interval.should eq 2.5.seconds
      end
    end

    describe "#scheduler_interval" do
      it "returns Time::Span from seconds" do
        config = JobsConfig.new
        config.scheduler_interval_seconds = 10.0
        config.scheduler_interval.should eq 10.seconds
      end
    end

    describe "#validate!" do
      it "passes for valid config" do
        config = JobsConfig.new
        config.validate! # should not raise
      end

      it "raises on zero workers" do
        config = JobsConfig.new
        config.workers = 0
        expect_raises(Amber::Exceptions::ConfigurationError, /jobs\.workers/) do
          config.validate!
        end
      end

      it "raises on negative polling interval" do
        config = JobsConfig.new
        config.polling_interval_seconds = -1.0
        expect_raises(Amber::Exceptions::ConfigurationError, /polling_interval/) do
          config.validate!
        end
      end

      it "raises on zero scheduler interval" do
        config = JobsConfig.new
        config.scheduler_interval_seconds = 0.0
        expect_raises(Amber::Exceptions::ConfigurationError, /scheduler_interval/) do
          config.validate!
        end
      end
    end
  end
end
