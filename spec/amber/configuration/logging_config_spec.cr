require "../../spec_helper"

module Amber::Configuration
  describe LoggingConfig do
    describe "defaults" do
      it "has sensible default values" do
        config = LoggingConfig.new
        config.severity.should eq "debug"
        config.colorize.should be_true
        config.color.should eq "light_cyan"
        config.filter.should eq ["password", "confirm_password"]
        config.skip.should eq([] of String)
      end
    end

    describe "YAML deserialization" do
      it "deserializes from YAML" do
        yaml = <<-YAML
        severity: "warn"
        colorize: false
        color: "red"
        filter:
          - password
          - api_key
        skip:
          - healthcheck
        YAML

        config = LoggingConfig.from_yaml(yaml)
        config.severity.should eq "warn"
        config.colorize.should be_false
        config.color.should eq "red"
        config.filter.should eq ["password", "api_key"]
        config.skip.should eq ["healthcheck"]
      end
    end

    describe "#severity_level" do
      it "parses debug severity" do
        config = LoggingConfig.new
        config.severity = "debug"
        config.severity_level.should eq Log::Severity::Debug
      end

      it "parses warn severity" do
        config = LoggingConfig.new
        config.severity = "warn"
        config.severity_level.should eq Log::Severity::Warn
      end

      it "parses info severity" do
        config = LoggingConfig.new
        config.severity = "info"
        config.severity_level.should eq Log::Severity::Info
      end

      it "parses error severity" do
        config = LoggingConfig.new
        config.severity = "error"
        config.severity_level.should eq Log::Severity::Error
      end
    end

    describe "#color_symbol" do
      it "maps color name to symbol" do
        config = LoggingConfig.new
        config.color = "red"
        config.color_symbol.should eq :red
      end

      it "returns default for unknown color" do
        config = LoggingConfig.new
        config.color = "nonexistent"
        config.color_symbol.should eq :light_cyan
      end
    end

    describe "#validate!" do
      it "passes for valid severity" do
        config = LoggingConfig.new
        config.severity = "info"
        config.validate! # should not raise
      end

      it "raises for invalid severity" do
        config = LoggingConfig.new
        config.severity = "invalid"
        expect_raises(Amber::Exceptions::ConfigurationError, /logging\.severity/) do
          config.validate!
        end
      end
    end
  end
end
