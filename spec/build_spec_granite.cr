require "./build_spec_helper"

module Amber::CLI
  describe "building a generated app using granite model and slang template" do
    cleanup
    generate_app("-t", "slang")

    it "check formatting" do
      system("crystal tool format --check").should be_true
    end

    it "shards update - dependencies" do
      system("shards update --ignore-crystal-version").should be_true
    end

    it "shards build - generates a binary" do
      system("shards build #{TEST_APP_NAME}").should be_true
    end

    it "executes specs" do
      system("crystal spec").should be_true
    end
  end

  describe "building a generated app using granite model and ecr template" do
    cleanup
    generate_app("-t", "ecr")

    it "check formatting" do
      system("crystal tool format --check").should be_true
    end

    it "shards update - dependencies" do
      system("shards update --ignore-crystal-version ").should be_true
    end

    it "shards build - generates a binary" do
      system("shards build #{TEST_APP_NAME}").should be_true
    end

    it "executes specs" do
      system("crystal spec").should be_true
    end
  end
end
