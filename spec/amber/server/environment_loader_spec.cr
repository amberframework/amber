require "../../../spec_helper"

describe Amber::EnvironmentLoader do
  it "raises error for non existent environment settings" do
    expect_raises Amber::Exceptions::Environment do
      Amber::EnvironmentLoader.new("unknown", "./spec/support/config/")
    end
  end

  it "load settings from YAML file" do
    environment = Amber::EnvironmentLoader.new(:fake_env, "./spec/support/config/")
    environment.settings.should be_a Amber::Settings
  end

  it "loads encrypted YAML settings" do
    ENV[Amber::SECRET_KEY] = "mnDiAY4OyVjqg5u0wvpr0MoBkOGXBeYo7_ysjwsNzmw"
    environment = Amber::EnvironmentLoader.new(:production, "./spec/support/config/")
    environment.settings.should be_a Amber::Settings
  end
end
