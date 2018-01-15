require "../../../../spec_helper"
require "../../../../support/helpers/cli_helper"

require "cli/spec"

include CLIHelper
include Cli::Spec::Helper

module Amber::CLI
  extend Helpers

  describe "amber pipelines" do
    begin
      ENV["CRYSTAL_CLI_ENV"] = "test"

      context "in an `amber new` with default options" do
        cleanup
        scaffold_app(TESTING_APP)
        output = ""

        describe "with the default routes" do
          MainCommand.run %w(pipelines) { |cmd| output = cmd.out.gets_to_end }
          output_lines = route_table_rows(output)

          it "outputs the correct headers" do
            headers = %w(Pipe Plug)
            headers.each do |header|
              output.should contain header
            end
          end

          it "outputs the default pipeline names" do
            pipeline_names = %w(web static)
            pipeline_names.each do |pipeline|
              output.should contain pipeline
            end
          end

          it "outputs the plugs for the pipelines" do
            plugs = %w(
              Amber::Pipe::Error
              Amber::Pipe::Logger
              Amber::Pipe::Session
              Amber::Pipe::Flash
              Amber::Pipe::CSRF
              Amber::Pipe::Reload
              Amber::Pipe::Error
              Amber::Pipe::Static
            )

            plugs.each do |plug|
              output.should contain plug
            end
          end
        end
      end
    ensure
      cleanup
    end
  end
end
