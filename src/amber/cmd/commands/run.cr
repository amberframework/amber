require "icr"
require "cli"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "r", aliased: "run"

    class Run < Cli::Command
      command_name "run"

      class Options
        string %w(-p --port), desc: "# PORT number to listen.", default: "3000"
        string %w(-e --environment), desc: "# AMBER_ENV environment (Production, Development, Staging).", default: "development"
      end

      class Help
        caption "# Boots Amber server"
      end

      def run
        release = "--release" if options.e.downcase == "production"
        puts "💎  Crystalizing...".colorize(:dark_gray)
        `crystal build #{release} $(ls ./src/*.cr | sort -n | head -1) -o app`
        puts "💎  Crystalization complete!".colorize(:dark_gray)
        Process.run(
          "PORT=#{options.p} AMBER_ENV=#{options.e} ./app",
          shell: true, output: true, error: true
         )
      end
    end
  end
end
