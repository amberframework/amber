require "../../spec_helper"

module Launch::Environment
  describe Loader do
    Dir.cd CURRENT_DIR

    it "raises error for non existent environment settings" do
      expect_raises Launch::Exceptions::Environment do
        Loader.new("unknown", "./spec/support/config/")
      end
    end

    it "load settings from YAML file" do
      environment = Loader.new(:fake_env, "./spec/support/config/")
      environment.settings.should be_a Launch::Environment::Settings
    end

    it "loads encrypted YAML settings" do
      environment = Loader.new(:production, "./spec/support/config/")
      environment.settings.should be_a Launch::Environment::Settings
    end
  end
end
