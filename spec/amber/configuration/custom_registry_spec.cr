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

    it "loads a custom config from YAML" do
      Amber::Configuration.register_custom("spec_yaml_custom", SpecCustomConfig.new)

      yaml = <<-YAML
      api_key: "my-api-key"
      timeout: 60
      YAML

      loaded = Amber::Configuration.load_custom_from_yaml("spec_yaml_custom", yaml)
      loaded.should_not be_nil
      loaded = loaded.not_nil!.as(SpecCustomConfig)
      loaded.api_key.should eq "my-api-key"
      loaded.timeout.should eq 60
    end

    it "returns nil for unregistered custom config keys" do
      loaded = Amber::Configuration.load_custom_from_yaml("nonexistent_key", "key: value")
      loaded.should be_nil
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
