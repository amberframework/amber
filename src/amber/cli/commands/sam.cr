require "cli"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    class Sam < Command
      command_name "sam"

      SAM_PATH = "sam.cr"

      class Options
        # NOTE: command definition is needed only to be displayed on help output
        arg_array "command", desc: "Sam command to be invoked"
        unknown
        help
      end

      class Help
        header <<-EOS
          Invokes Sam based task. Powered by Sam (https://github.com/imdrasil/sam.cr).
          To list all available tasks use:
            $ amber sam help
        EOS
        caption "# Invoke Sam task"
      end

      def run
        if File.exists?(SAM_PATH)
          Helpers.run("crystal run sam.cr -- #{ARGV[1..-1].join(" ")}")
        else
          exit! "Sam file is not found.", error: true
        end
      end
    end
  end
end
