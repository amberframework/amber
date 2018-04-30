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
      MainCommand.run ["generate", "error"]
      MainCommand.run ["generate", "scaffold", "Animal"] | temp_options
      MainCommand.run ["generate", "scaffold", "Post"] | options
      MainCommand.run ["generate", "scaffold", "PostComment"] | (options + ["post:reference"])
      MainCommand.run ["generate", "model", "Bat"] | options
      MainCommand.run ["generate", "migration", "Crocodile"] | options
      MainCommand.run ["generate", "mailer", "Dinosaur"] | options
      MainCommand.run ["generate", "socket", "Eagle"] | ["soar", "nest"]
      MainCommand.run ["generate", "channel", "Falcon"]

      prepare_yaml(Dir.current)
      Amber::CLI.env = "test"
      Amber::CLI.settings.logger = Amber::Environment::Logger.new(nil)

      puts "RUNNING: shards install --production"
      `shards install --production`

      puts "RUNNING: shards build"
      build_result = `shards build`

      # HACK: Travis CI fails randomly to migrate pg database,
      # so this loop ensure models are available before executing specs
      loop do
        puts "RUNNING: amber db drop create"
        MainCommand.run ["db", "drop", "create", "migrate"]
        puts "RUNNING: amber exec"
        puts "INFO: Verify models before executing specs"
        io = IO::Memory.new
        Process.run("bin/amber", ["exec", "User.first; Animal.first; Post.first; PostComment.first; Bat.first"], output: io, error: io)
        output = io.to_s
        error = (output =~ /(E|e)rror/)
        puts "INFO: Models verification completed with output:"
        puts output
        break if error.nil?
        puts "INFO: Trying again..."
      end

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
