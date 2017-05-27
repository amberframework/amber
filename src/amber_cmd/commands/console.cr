require "icr"
require "cli"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "c", aliased: "console"

    class Console < Cli::Command
      def run
        libs = ["require \"amber\"", "require \"./config/*\""] of String
        code = libs.join ';'
        Icr::Console.new(true).start(code)
      end
    end
  end
end
