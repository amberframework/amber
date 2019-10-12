require "./build_spec_helper"

module Amber::CLI
  describe "building a generated app using granite model and slang template" do
    it "check formatting" do
      generate_app("-t", "slang")
      system("crystal tool format --check").should be_true
      cleanup
    end

    it "shards update - dependencies" do
      generate_app("-t", "slang")
      system("shards update").should be_true
      cleanup
    end

    it "shards check - dependencies" do
      generate_app("-t", "slang")
      system("shards check").should be_true
      cleanup
    end

    it "shards build - generates a binary" do
      generate_app("-t", "slang")
      system("shards build #{TEST_APP_NAME}").should be_true
      cleanup
    end

    it "executes specs" do
      generate_app("-t", "slang")
      system("crystal spec").should be_true
      cleanup
    end
  end

  describe "building a generated app using granite model and ecr template" do
    it "check formatting" do
      generate_app("-t", "ecr")
      system("crystal tool format --check").should be_true
      cleanup
    end

    it "shards update - dependencies" do
      generate_app("-t", "ecr")
      system("shards update").should be_true
      cleanup
    end

    it "shards check - dependencies" do
      generate_app("-t", "ecr")
      system("shards check").should be_true
      cleanup
    end

    it "shards build - generates a binary" do
      generate_app("-t", "ecr")
      system("shards build #{TEST_APP_NAME}").should be_true
      cleanup
    end

    it "executes specs" do
      generate_app("-t", "ecr")
      system("crystal spec").should be_true
      cleanup
    end
  end
end
