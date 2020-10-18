require "../../../../spec_helper"
require "../../../../support/helpers/cli_helper"

include CLIHelper

module Launch::CLI
  describe MainCommand::Generate do
    it "generates controller and views" do
      scaffold_app(TESTING_APP)
      MainCommand.run %w(generate error -y error)

      File.exists?("./src/controllers/error_controller.cr").should be_true
      File.exists?("./spec/controllers/error_controller_spec.cr").should be_true
      File.read("./spec/controllers/error_controller_spec.cr").should contain "ErrorController"

      ["forbidden", "not_found", "internal_server_error"].each do |view|
        File.exists?("./src/views/error/#{view}.ecr").should be_true
      end
      cleanup
    end
  end
end
