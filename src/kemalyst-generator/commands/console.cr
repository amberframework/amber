require "icr"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    class Console < Cli::Command
      def run
        libs = [] of String
        code = libs.join ';'
        Icr::Console.new(true).start(code)
      end
    end
  end
end
