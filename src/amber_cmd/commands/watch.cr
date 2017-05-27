require "cli"
require "sentry/sentry_command"

module Amber::CMD

  class MainCommand < Cli::Supercommand
    command "w", aliased: "watch"

    class Watch < Sentry::SentryCommand
      command_name "watch"

      def run
        options.watch << "./config/**/*.cr"
        options.watch << "./src/views/**/*.slang"
        super
      end
    end
  end
end
