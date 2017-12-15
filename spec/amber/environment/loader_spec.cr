require "../../../spec_helper"

module Amber::Environment
  describe Loader do
    Dir.cd CURRENT_DIR

    context "when path is empty" do
      it "loads default settings for existent environment" do
        loader = Loader.new("development", "")
        loader.settings.should be_a Amber::Environment::Settings
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
