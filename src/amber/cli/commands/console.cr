require "icr"
require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "c", aliased: "console"

    class Console < ::Cli::Command
      command_name "console"

      class Options
        bool ["-d", "--debug"], desc: "# Runs console in debug mode.", default: false
      end

      def run
        Icr::Console.new(options.d?).start("require \"./config/*\"")
      end

      class Help
        caption "# Starts Amber console"
      end
    end
  end
end
