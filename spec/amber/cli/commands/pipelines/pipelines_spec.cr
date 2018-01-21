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

        pipeline_names = %w(web static)

        web_default_plugs = %w(
          Amber::Pipe::PoweredByAmber
          Amber::Pipe::Error
          Amber::Pipe::Logger
          Amber::Pipe::Session
          Amber::Pipe::Flash
          Amber::Pipe::CSRF
          Amber::Pipe::Reload
        )

        static_default_plugs = %w(
          Amber::Pipe::PoweredByAmber
          Amber::Pipe::Error
          Amber::Pipe::Static
        )


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
            pipeline_names.each do |pipeline|
              output.should contain pipeline
            end
          end

          it "outputs the plugs for the pipelines" do
            (web_default_plugs + static_default_plugs).each do |plug|
              output.should contain plug
            end
          end

          it "maintains the correct order of pipelines and plugs" do
            in_correct_order = %w(Plug) + %w(web) + web_default_plugs + %w(static) + static_default_plugs

            output_lines
            .reject { |line| line.empty? }
            .each_with_index do |line, index|
              line.should contain (in_correct_order[index])
            end
          end
        end
      end
    ensure
      cleanup
    end
  end
end
