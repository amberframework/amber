require "cli"
require "sentry/sentry_command"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "s", aliased: "sidekiq"

    class Sidekiq < Sentry::SentryCommand
      command_name "sidekiq"

      def run
        options.watch << "./config/**/*.cr"
        super
      end
    end
  end
end

class Sentry::SentryCommand::Options
  def self.get_name
    "sidekiq"
  end
end
