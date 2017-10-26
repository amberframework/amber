require "../../spec_helper"
require "../../../src/amber/tasks/**"

class FirstFakeTask < Amber::Tasks::Task
  def description
    "First fake task"
  end

  def perform
    "First Fake Task"
  end
end

class Second::FakeTask < Amber::Tasks::Task
  def perform
    "Second Fake Task"
  end

  def description
    "Second fake task"
  end
end

module Amber::Tasks
  describe Runner do
    describe "#tasks" do
      it "returns a list of defined tasks" do
        Runner.tasks.should be_a Array(Task)
        Runner.tasks.size.should eq 2
      end
    end

    describe "#definitions" do
      it "outputs tasks information" do
        Runner.definitions.should eq(
          %(FirstFakeTask\t\t #First fake task\nSecond::FakeTask\t\t #Second fake task\n)
        )
      end
    end

    describe "#perform" do
      it "executes the tasks operation" do
        runner = Runner.new("firstfaketask")

        runner.perform.should eq "First Fake Task"
      end

      it "does not find invalid task name" do
        runner = Runner.new("invalid_task")

        runner.perform.should be_nil
      end

      it "performs namespaced task" do
        runner = Runner.new("second::faketask")

        runner.perform.should eq "Second Fake Task"
      end
    end
  end
end
