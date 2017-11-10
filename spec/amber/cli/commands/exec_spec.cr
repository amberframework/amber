require "../../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  describe "amber exec" do
    cleanup
    scaffold_app(TESTING_APP)

    it "executes one-liners from the first command-line argument" do
      MainCommand.run(["exec", "[:a, :b, :c] + [:d]"]).should eq "[:a, :b, :c, :d]\n"
    end

    it "executes a .cr file from the first command-line argument" do
      File.write "amber_exec_spec_test.cr", "puts([:a] + [:b])"
      MainCommand.run(["exec", "amber_exec_spec_test.cr"]).should eq "[:a, :b]\n"
      File.delete("amber_exec_spec_test.cr")
    end

    it "attempts to run the specified editor in zero-arg mode" do
      MainCommand.run(["exec", "-e", "a-non-existent-editor"]).should eq ""
    end

    cleanup

    it "complains if not in the root of a project" do
      MainCommand.run(["exec", ":hello"]).should eq "error: 'amber exec' can only be used from the root of a valid amber project"
    end
  end
end
