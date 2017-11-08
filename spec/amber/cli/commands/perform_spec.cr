require "../../../spec_helper"
require "../../tasks/**"
require "../../../support/fixtures/tasks_fixtures"

module Amber::CLI
  describe "amber perform" do
    runner = MainCommand::Perform.run(["faketask"])

    it "performs a tasks via command line" do
      runner.should eq "Fake task completed!"
    end

    it "performs a tasks via command line alias" do
      runner.should eq "Fake task completed!"
    end

    context "listing all tasks" do
      runner = MainCommand::Perform.run(["-l", "faketask"])
      it "shows task description" do
        runner.should eq expected_tasks_output
      end
    end
  end
end
