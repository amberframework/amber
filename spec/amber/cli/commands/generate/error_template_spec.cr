require "../../../../spec_helper"
require "../../../../support/fixtures/cli/generators/error/*"

module Amber::CLI
  describe MainCommand::Generate do
    begin
      describe "amber generate error" do
        context "in an `amber new` app with default options" do
          ENV["AMBER_ENV"] = "test"
          MainCommand.run ["new", TESTING_APP]
          Dir.cd(TESTING_APP)
          MainCommand.run %w(generate error a)

          it "generates expected controller class" do
            expected = CLIFixtures::ErrorControllerFixture.expected_error_controller
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

          {% if flag?(:run_builds) || flag?(:run_test_app_builds)%}

            describe "error_controller_spec.cr" do
              `shards build`
              result = `crystal spec ./spec/controllers/error_controller_spec.cr`
              
              it "can be executed" do
                result.should contain "Finished in"
              end

              it "has no errors" do
                result.should_not contain "Error in line"
              end

              it "has no failures" do
                result.should_not contain "Failures"
              end
            end

          {% end %}

        end
      end
    ensure
      Amber::CLI::Spec.cleanup
    end
  end
end
