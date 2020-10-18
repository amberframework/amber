require "../../../spec_helper"
require "../../../support/helpers/cli_helper"
require "../../../../src/launch/support/file_encryptor"

include CLIHelper

module Launch::CLI
  describe "launch encrypt" do
    it "creates a credentials file" do
      scaffold_app(TESTING_APP)
      MainCommand.run ["encrypt", "--noedit"]
      File.exists?("config/credentials.yml.enc").should be_true
      cleanup
    end

    it "unencrypts credentials" do
      scaffold_app(TESTING_APP)
      MainCommand.run ["encrypt", "--noedit"]
      String.new(Support::FileEncryptor.read("./config/credentials.yml.enc")).should contain "secret_key_base:"
      cleanup
    end

    it "creates a 44 characters secret key in .encryption_key" do
      scaffold_app(TESTING_APP)
      MainCommand.run ["encrypt", "--noedit"]
      File.read("./config/master.key").size.should eq 44
      cleanup
    end
  end
end
