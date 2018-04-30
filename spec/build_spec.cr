require "./spec_helper"
require "./support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  begin
    describe "building a generated app" do
      ENV["AMBER_ENV"] = "test"

      cleanup
      scaffold_app(TESTING_APP)

      options = ["user:reference", "name:string", "body:text", "age:integer", "published:bool"]
      temp_options = options - ["user:reference", "age:integer"]
      MainCommand.run ["generate", "auth", "User"] | (options - ["user:reference"])
      sleep 1.second
      MainCommand.run ["generate", "error"]
      sleep 1.second
      MainCommand.run ["generate", "scaffold", "Animal"] | temp_options
      sleep 1.second
      MainCommand.run ["generate", "scaffold", "Post"] | options
      sleep 1.second
      MainCommand.run ["generate", "scaffold", "PostComment"] | (options + ["post:reference"])
      sleep 1.second
      MainCommand.run ["generate", "model", "Bat"] | options
      sleep 1.second
      MainCommand.run ["generate", "migration", "Crocodile"] | options
      MainCommand.run ["generate", "mailer", "Dinosaur"] | options
      MainCommand.run ["generate", "socket", "Eagle"] | ["soar", "nest"]
      MainCommand.run ["generate", "channel", "Falcon"]

      prepare_yaml(Dir.current)
      Amber::CLI.env = "test"
      Amber::CLI.settings.logger = Amber::Environment::Logger.new(nil)

      puts "RUNNING: shards install --production"
      `shards install --production`

      puts "RUNNING: shards build #{TEST_APP_NAME}"
      build_result = `shards build #{TEST_APP_NAME}`

      puts "RUNNING: amber db drop create migrate"
      MainCommand.run ["db", "drop", "create", "migrate"]

      it "generates a binary" do
        puts build_result unless File.exists?("bin/#{TEST_APP_NAME}")
        File.exists?("bin/#{TEST_APP_NAME}").should be_true
      end

      context "crystal spec" do
        puts "RUNNING: crystal spec"
        spec_result = `crystal spec`

        it "can be executed" do
          puts spec_result unless spec_result.includes? "Finished in"
          spec_result.should contain "Finished in"
        end

        it "has no errors" do
          puts spec_result if spec_result.includes? "Error in line"
          spec_result.should_not contain "Error in line"
        end

        it "has no failures" do
          puts spec_result if spec_result.includes? "Failures"
          spec_result.should_not contain "Failures"
        end
      end
    end
  ensure
    cleanup
  end
end
# Trigger build at Mon Apr 30 14:42:45 EST 2018
# Trigger build at Mon Apr 30 14:52:12 EST 2018
# Trigger build at Mon Apr 30 14:55:17 EST 2018
# Trigger build at Mon Apr 30 14:58:21 EST 2018
# Trigger build at Mon Apr 30 16:14:26 EST 2018
# Trigger build at Mon Apr 30 16:17:30 EST 2018
# Trigger build at Mon Apr 30 16:20:33 EST 2018
# Trigger build at Mon Apr 30 16:23:37 EST 2018
# Trigger build at Mon Apr 30 16:26:40 EST 2018
# Trigger build at Mon Apr 30 16:29:44 EST 2018
# Trigger build at Mon Apr 30 16:32:49 EST 2018
# Trigger build at Mon Apr 30 16:35:52 EST 2018
# Trigger build at Mon Apr 30 16:38:56 EST 2018
# Trigger build at Mon Apr 30 16:41:59 EST 2018
# Trigger build at Mon Apr 30 16:45:05 EST 2018
# Trigger build at Mon Apr 30 16:48:12 EST 2018
# Trigger build at Mon Apr 30 16:51:16 EST 2018
# Trigger build at Mon Apr 30 16:54:19 EST 2018
# Trigger build at Mon Apr 30 16:57:23 EST 2018
# Trigger build at Mon Apr 30 17:00:26 EST 2018
# Trigger build at Mon Apr 30 17:03:31 EST 2018
