require "icr"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "c", aliased: "console"

    class Console < Cli::Command
      def run
        libs = ["require \"kemalyst\"", "require \"./config/*\""] of String
        code = libs.join ';'
        Icr::Console.new(true).start(code)
      end
    end
  end
end
