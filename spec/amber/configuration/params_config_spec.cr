require "../../spec_helper"

module Amber::Configuration
  describe ParamsConfig do
    describe "defaults" do
      it "bounds every parameter dimension" do
        config = ParamsConfig.new
        config.max_array_index.should eq 100
        config.max_array_index_gap.should eq 32
        config.max_array_padding.should eq 1_000
        config.max_params.should eq 1_000
        config.max_nesting_depth.should eq 32
        config.max_key_bytes.should eq 1_024
        config.max_value_bytes.should eq 1_048_576
        config.max_form_body_bytes.should eq 8_388_608
      end
    end

    describe "YAML deserialization" do
      it "reads the params section of an application config" do
        config = AppConfig.from_yaml("params:\n  max_array_index: 250\n")
        config.params.max_array_index.should eq 250
        config.params.max_params.should eq 1_000
      end
    end

    describe "#validate!" do
      it "rejects a limit below 1" do
        config = ParamsConfig.new
        config.max_params = 0

        expect_raises(Amber::Exceptions::ConfigurationError, /params.max_params/) do
          config.validate!
        end
      end
    end

    describe "environment overrides" do
      it "reads AMBER_PARAMS_MAX_ARRAY_INDEX" do
        ENV["AMBER_PARAMS_MAX_ARRAY_INDEX"] = "7"
        begin
          config = EnvOverride.apply_all(AppConfig.new)
          config.params.max_array_index.should eq 7
        ensure
          ENV.delete("AMBER_PARAMS_MAX_ARRAY_INDEX")
        end
      end
    end
  end
end
