require "../generator"

module Kemalyst::Generator

  class MainCommand < Cli::Supercommand
    command "g", aliased: "generate"

    class Generate < Cli::Command
      class Options
        arg "type", desc: "resource", required: true
        arg "name", desc: "name of resource", required: true
      end

      def run
        generator = ::Generator.new(args.name, ".")
        generator.generate args.type
      end
    end
  end
end
