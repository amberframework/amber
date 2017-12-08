require "../../../spec_helper"

module Amber::Environment
  describe Loader do
    Dir.cd CURRENT_DIR

    it "raises error for non existent environment settings" do
      expect_raises Amber::Exceptions::Environment do
        Loader.new("unknown", "./spec/support/config/")
      end
    end

    it "load settings from YAML file" do
      environment = Loader.new(:fake_env, "./spec/support/config/")
      environment.settings.should be_a Amber::Environment::Settings
    end

    it "loads encrypted YAML settings" do
      environment = Loader.new(:production, "./spec/support/config/")
      environment.settings.should be_a Amber::Environment::Settings
    end
  end
end
