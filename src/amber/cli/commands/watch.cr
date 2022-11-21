require "cli"
require "../helpers/sentry"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "w", aliased: "watch"

    class Watch < Sentry::SentryCommand
      command_name "watch"

      class Options
        bool "--no-color", desc: "disable colored output", default: false
        help
      end

      class Help
        header "Starts Amber development server and rebuilds on file changes"
        caption "Starts Amber development server and rebuilds on file changes"
      end

      def run
        CLI.toggle_colors(options.no_color?)
        super
      end
    end
  end
end
