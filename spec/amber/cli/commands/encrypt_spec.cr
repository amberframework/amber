require "../../../spec_helper"
require "../../../support/helpers/cli_helper"
require "../../../../src/amber/support/file_encryptor"

include CLIHelper

module Amber::CLI
  describe "amber encrypt" do
    it "creates a hidden .test.enc file" do
      scaffold_app(TESTING_APP)
      MainCommand.run ["encrypt", "test"]
      File.exists?("config/environments/.test.enc").should be_true
      cleanup
    end

    it "unencrypts .test.enc" do
      scaffold_app(TESTING_APP)
      MainCommand.run ["encrypt", "test"]
      String.new(Support::FileEncryptor.read("./config/environments/.test.enc")).should contain "port: 3000"
      cleanup
    end

    it "creates a 44 characters secret key in .encryption_key" do
      scaffold_app(TESTING_APP)
      MainCommand.run ["encrypt", "test"]
      File.read(".encryption_key").size.should eq 44
      cleanup
    end

    it "does not execute shell metacharacters in the editor option" do
      scaffold_app(TESTING_APP)
      # Create an encrypted file to trigger the edit step
      MainCommand.run ["encrypt", "test"]

      marker = "amber_encrypt_editor_pwned"
      File.delete(marker) if File.exists?(marker)

      expect_raises(Exception) do
        # Use an editor with command injection
        MainCommand.run ["encrypt", "test", "-e", "sh -c 'touch #{marker}' #"]
      end

      File.exists?(marker).should be_false
      cleanup
    end
  end
end
