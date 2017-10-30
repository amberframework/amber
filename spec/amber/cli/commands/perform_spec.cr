require "../../../spec_helper"
require "../../tasks/**"
require "../../../support/fixtures/tasks_fixtures"

module Amber::CLI
  describe MainCommand::Perform do
    runner = MainCommand.run ["perform", "faketask"]

    it "performs a tasks via command line" do
      runner.should eq "Fake task completed!"
    end

    it "performs a tasks via command line alias" do
      runner.should eq "Fake task completed!"
    end

    context "listing all tasks" do
      output = %(FirstFakeTask\t\t #First fake task\nSecond::FakeTask\t\t #Second fake task\nFakeTask\t\t #Fake command task\n)
      runner = MainCommand.run ["p", "-l", "faketask"]

      it "shows task description" do
        runner.should eq output
      end
    end
  end
end
