require "../../../spec_helper"

module Amber::Environment
  describe EnvironmentLoader do
    Dir.cd CURRENT_DIR

    it "raises error for non existent environment settings" do
      expect_raises Amber::Exceptions::Environment do
        EnvironmentLoader.new("unknown", "./spec/support/config/", Amber.file_encryptor)
      end
    end

    it "load settings from YAML file" do
      environment = EnvironmentLoader.new(:fake_env, "./spec/support/config/", Amber.file_encryptor)
      environment.settings.should be_a Amber::Environment::Settings
    end

    it "loads encrypted YAML settings" do
      environment = EnvironmentLoader.new(:production, "./spec/support/config/", Amber.file_encryptor)
      environment.settings.should be_a Amber::Environment::Settings
    end
  end
end
