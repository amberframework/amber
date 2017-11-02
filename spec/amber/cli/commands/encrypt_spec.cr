require "../../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  describe "amber encrypt" do
    arg = "test"
    cleanup
    scaffold_app(TESTING_APP)
    MainCommand.run ["encrypt", "test"]

    it "creates a hidden .#{arg}.enc file" do
      File.exists?("config/environments/.#{arg}.enc").should be_true
    end

    it "creates a 44 characters secret key in .amber_secret_key" do
      File.read(".amber_secret_key").size.should eq 44
    end

    cleanup
  end
end
