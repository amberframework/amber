require "cli"
require "sentry/sentry_command"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "s", aliased: "sidekiq"

    class Sidekiq < Sentry::SentryCommand
      command_name "sidekiq"

      def run
        options.watch << "./config/**/*.cr"
        process_runner = Sentry::ProcessRunner.new(
          process_name: "sidekiq",
          build_command: "crystal build src/sidekiq.cr",
          run_command: "./sidekiq",
          build_args: [] of String,
          run_args: [] of String,
          should_build: !options.no_build?,
          files: options.watch
        )

        process_runner.run
      end
    end
  end
end
