require "../../spec_helper"

describe Amber::Support::LogColor do
  describe ".paint" do
    it "colors the value when enabled" do
      previous = Colorize.enabled?
      Colorize.enabled = true
      begin
        Amber::Support::LogColor.paint("ready", :green, enabled: true).to_s.should eq "\e[32mready\e[39m"
      ensure
        Colorize.enabled = previous
      end
    end

    it "returns the plain value when disabled" do
      Amber::Support::LogColor.paint("ready", :green, enabled: false).to_s.should eq "ready"
    end

    it "keeps the value plain when the app disabled Colorize" do
      previous = Colorize.enabled?
      Colorize.enabled = false
      begin
        Amber::Support::LogColor.paint("ready", :green, enabled: true).to_s.should eq "ready"
      ensure
        Colorize.enabled = previous
      end
    end
  end
end
