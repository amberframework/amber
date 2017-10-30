require "../../../spec_helper"
require "../../../support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  begin
    describe MainCommand::Encrypt do
      context "application structure" do
        it "creates amber directory structure" do
          scaffold_app(TESTING_APP)
          MainCommand.run ["encrypt", "test"]
          assert_encrypted_files_exists?(".test.enc", ".amber_secret_key")
          cleanup
        end
      end
    end
  ensure
    cleanup
  end
end
