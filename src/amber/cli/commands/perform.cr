require "icr"
require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "p", aliased: "perform"

    class Perform < ::Cli::Command
      command_name "perform"

      class Options
        bool ["-l", "--list"], desc: "# Displays all tasks available", default: false
        arg "task", desc: "Name of the task to execute", required: true
      end

      class Help
        caption "# It run and performs tasks within the amber application scope"
      end

      def run
        if options.l?
          Amber::Tasks::Runner.definitions
        else
          Amber::Tasks::Runner.perform(args.task)
        end
      end
    end
  end
end
