require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "r", aliased: "run"

    class Run < Command
      command_name "run"

      class Options
        string %w(-p --port), desc: "# PORT number to listen.", default: "3000"
        string %w(-e --environment), desc: "# AMBER_ENV environment (Production, Development, Staging).", default: "development"
        bool "--no-color", desc: "# Disable colored output", default: false
        help
      end

      class Help
        caption "# Boots Amber server"
      end

      def run
        name = Sentry::SentryCommand::Options.get_name
        Dir.mkdir_p("bin")
        compile_command = "crystal build $(ls ./src/*.cr | sort -n | head -1) -o bin/#{name}"
        compile_command += " --release --no-debug" unless %w(development test).includes?(options.e.downcase)
        system(compile_command)
        Process.run(
          "PORT=#{options.p} AMBER_ENV=#{options.e} ./bin/#{name}",
          shell: true, output: true, error: true
        )
      end
    end
  end
end
