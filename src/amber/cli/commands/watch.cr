require "cli"
require "../helpers/process_runner"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "w", aliased: "watch"

    class Watch < ::Cli::Command
      class Options
        bool "--no-color", desc: "# Disable colored output", default: false
        help
      end

      class Help
        header <<-HEADER
        Starts amber development server and rebuilds on file changes.
        See `.amber.yml` for more settings.
        HEADER
      end

      def run
        CLI.toggle_colors(options.no_color?)
        process_runner = Helpers::ProcessRunner.new
        process_runner.run
      end
    end
  end
end
