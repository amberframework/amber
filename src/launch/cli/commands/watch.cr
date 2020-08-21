require "cli"
require "../helpers/sentry"

module Launch::CLI
  class MainCommand < ::Cli::Supercommand
    command "w", aliased: "watch"

    class Watch < Sentry::SentryCommand
      command_name "watch"

      class Options
        bool "--no-color", desc: "disable colored output", default: false
        help
      end

      class Help
        header "Starts Launch development server and rebuilds on file changes"
        caption "starts Launch development server and rebuilds on file changes"
      end

      def run
        CLI.toggle_colors(options.no_color?)
        super
      end
    end
  end
end
