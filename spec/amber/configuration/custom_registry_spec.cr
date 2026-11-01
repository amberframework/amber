require "../../spec_helper"

class SpecCustomConfig
  include YAML::Serializable

  property api_key : String = ""
  property timeout : Int32 = 30

  def initialize
  end
end

module Amber::Configuration
  describe "Custom Configuration Registry" do
    it "registers a custom config type" do
      # Register using the runtime method
      Amber::Configuration.register_custom("spec_custom", SpecCustomConfig.new)
      Amber::Configuration.custom_config_defaults.has_key?("spec_custom").should be_true
    end

    it "loads a custom config section from YAML as its registered type" do
      Amber::Configuration.register_custom("spec_yaml_custom", SpecCustomConfig.new)
      config = AppConfig.new
      config.custom_configs["spec_yaml_custom"] = <<-YAML
      api_key: "my-api-key"
      timeout: 60
      YAML

      loaded = config.custom(:spec_yaml_custom, SpecCustomConfig)

      loaded.api_key.should eq "my-api-key"
      loaded.timeout.should eq 60
    end

    it "raises a configuration error for an unregistered custom config key" do
      expect_raises(Amber::Exceptions::ConfigurationError, /nonexistent_key/) do
        AppConfig.new.custom(:nonexistent_key, SpecCustomConfig)
      end
    end

    it "provides defaults when YAML is not present" do
      Amber::Configuration.register_custom("spec_default_custom", SpecCustomConfig.new)
      default = Amber::Configuration.custom_config_defaults["spec_default_custom"]
      default.should be_a(SpecCustomConfig)
      default.as(SpecCustomConfig).api_key.should eq ""
      default.as(SpecCustomConfig).timeout.should eq 30
    end
  end
end
