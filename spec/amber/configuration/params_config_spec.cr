require "../../spec_helper"
require "file_utils"

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
      it "accepts the defaults" do
        ParamsConfig.new.validate!
      end

      it "rejects values outside each range, including type maximums" do
        config = ParamsConfig.new
        config.max_array_index_gap = Int32::MAX
        config.max_array_index = -1
        config.max_file_bytes = Int64::MAX

        error = expect_raises(Amber::Exceptions::ConfigurationError) do
          config.validate!
        end
        error.list_of_errors.size.should eq 3
        error.message.to_s.should contain("params.max_file_bytes must be between 1 and 1073741824")
        error.message.to_s.should contain("params.max_array_index_gap must be between 0 and 1000000")
      end

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

    describe "loading" do
      it "validates the effective V2 configuration at load time" do
        dir = File.tempname("amber-params-v2")
        Dir.mkdir_p(dir)
        File.write(File.join(dir, "params_test.yml"), "server:\n  port: 3000\nparams:\n  max_params: 0\n")
        begin
          expect_raises(Amber::Exceptions::ConfigurationError, /params.max_params/) do
            Amber::Environment::Loader.new(:params_test, dir).settings
          end
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "carries params and AMBER_PARAMS_* overrides through the V1 settings path" do
        dir = File.tempname("amber-params-v1")
        Dir.mkdir_p(dir)
        File.write(File.join(dir, "params_test.yml"), "name: v1_app\nparams:\n  max_params: 50\n")
        ENV["AMBER_PARAMS_MAX_ARRAY_INDEX"] = "5"
        begin
          settings = Amber::Environment::Loader.new(:params_test, dir).settings
          settings.params.max_params.should eq 50
          settings.params.max_array_index.should eq 5
        ensure
          ENV.delete("AMBER_PARAMS_MAX_ARRAY_INDEX")
          FileUtils.rm_rf(dir)
        end
      end
    end
  end
end
