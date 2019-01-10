require "../../../../spec_helper"
require "../../../../support/fixtures/cli/generate_fixtures"
require "../../../../support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  include Fixtures::CLI::Generate
  describe MainCommand::Generate do
    begin
      describe "amber generate error" do
        context "in an `amber new` app with default options" do
          cleanup
          scaffold_app(TESTING_APP)
          MainCommand.run %w(generate error error)

          it "generates expected controller class" do
            expected = ErrorController.expected_error_controller
            File.read("./src/controllers/error_controller.cr").should eq expected
          end

          it "generates a controller spec file" do
            File.exists?("./spec/controllers/error_controller_spec.cr").should be_true
          end

          it "generates a controller spec file with correct class name" do
            expected = "ErrorController"
            File.read("./spec/controllers/error_controller_spec.cr").should contain expected
          end

          it "generates view files" do
            ["forbidden", "not_found", "internal_server_error"].each do |view|
              File.exists?("./src/views/error/#{view}.slang").should be_true
            end
          end
        end
      end
    ensure
      cleanup
    end
  end
end
