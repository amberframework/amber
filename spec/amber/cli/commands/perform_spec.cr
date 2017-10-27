require "../../../spec_helper"
require "../../tasks/**"

class FakeTask < Amber::Tasks::Task
  def description
    "Fake command task"
  end

  def perform
    "Fake task completed!"
  end
end

module Amber::CLI
  describe MainCommand::Perform do
    it "performs a tasks via command line" do
      runner = MainCommand.run ["perform", "faketask"]

      runner.should eq "Fake task completed!"
    end

    it "performs a tasks via command line alias" do
      runner = MainCommand.run ["p", "faketask"]

      runner.should eq "Fake task completed!"
    end

    it "shows task description" do
      runner = MainCommand.run ["p", "-l", "faketask"]

      runner.should eq(
        %(FirstFakeTask\t\t #First fake task\nSecond::FakeTask\t\t #Second fake task\nFakeTask\t\t #Fake command task\n)
      )
    end
  end
end
