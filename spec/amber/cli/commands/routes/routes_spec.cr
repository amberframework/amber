require "../../../../spec_helper"
require "../../../../support/helpers/cli_helper"

require "cli/spec"

include CLIHelper
include Cli::Spec::Helper

module Amber::CLI
  extend Helpers
  describe "amber routes" do
    begin
      ENV["CRYSTAL_CLI_ENV"] = "test"
      context "in an `amber new` app with default options" do
        cleanup
        scaffold_app(TESTING_APP)
        output = ""

        describe "with the default routes" do

          MainCommand.run %w(routes) { |cmd| output = cmd.out.gets_to_end }
          output_lines = route_table_rows(output)

          it "outputs the correct headers" do
            headers = %w(Verb Controller Action Pipeline Scope) << "URI Pattern"
            headers.each do |header|
              output.should contain header
            end
          end

          it "outputs the static file handler" do
            expected = "Amber::Controller::Static"
            output.should contain expected
            line = output_lines.find(""){ |line| line.includes? expected }
            expectations = %w(get Amber::Controller::Static index static /*)
            expectations.each do |expectation|
              line.should contain expectation
            end
          end

          it "outputs the HomeController index action" do
            expected = "HomeController"
            output.should contain expected
            line = output_lines.find(""){ |line| line.includes? expected }
            expectations = %w(get HomeController index web /)
            expectations.each do |expectation|
              line.should contain expectation
            end
          end
        end

        describe "with a websocket route" do
          add_routes :web, %(websocket "/electric", ElectricSocket)
          MainCommand.run %w(routes) { |cmd| output = cmd.out.gets_to_end }
          output_lines = route_table_rows(output)

          it "outputs the web socket route" do
            expected = "websocket"
            output.should contain expected
            line = output_lines.find(""){ |line| line.includes? expected }
            expectations = %w(websocket ElectricSocket web /electric)
            expectations.each do |expectation|
              line.should contain expectation
            end
          end
        end

      end
    ensure
      cleanup
    end
  end
end
