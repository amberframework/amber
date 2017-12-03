require "cli"
require "../helpers/sentry"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "w", aliased: "watch"

    class Watch < Sentry::SentryCommand
      command_name "watch"

      class Options
        help
      end

      class Help
        caption "# Starts amber server and rebuilds on file changes"
      end

      def run
        options.watch << "./config/**/*.cr"
        options.watch << "./src/views/**/*.slang"
        super
      end
    end
  end
end
