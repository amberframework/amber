{% if flag?(:run_build_tests) %}
require "../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  begin
    describe "building a generated app" do
      ENV["AMBER_ENV"] = "test"
      MainCommand.run ["new", TESTING_APP]
      Dir.cd(TESTING_APP)

      options = ["user:reference", "name:string", "body:text", "age:integer", "published:bool"]
      temp_options = options - ["user:reference", "age:integer"]
      # MainCommand.run ["generate", "auth", "User"] | (options - ["user:reference"])
      MainCommand.run ["generate", "scaffold", "Animal"] | temp_options
      # MainCommand.run ["generate", "scaffold", "Post"] | options
      # MainCommand.run ["generate", "scaffold", "PostComment"] | (options + ["post:reference"])
      # MainCommand.run ["generate", "model", "Bat"] | options
      # MainCommand.run ["generate", "migration", "Crocodile"] | options
      # MainCommand.run ["generate", "mailer", "Dinosaur"] | options
      # MainCommand.run ["generate", "socket", "Eagle"] | ["soar", "nest"]
      # MainCommand.run ["generate", "channel", "Falcon"]

      prepare_yaml(Dir.current)

      build_result = `shards build`
      db_result = `amber db drop create migrate`

      it `generates a binary` do
        puts build_result unless File.exists?("bin/#{TEST_APP_NAME}")
        File.exists?("bin/#{TEST_APP_NAME}").should be_true
      end

      context "crystal spec" do
        spec_result = `crystal spec`

        it "can be executed" do
          spec_result.should contain "Finished in"
        end

        it "has no errors" do
          spec_result.should_not contain "Error in line"
        end

        it "has no failures" do
          spec_result.should_not contain "Failures"
        end
      end
    end
  ensure
    cleanup
  end
end
{% end %}
