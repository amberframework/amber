require "../generator"

module Kemalyst::Generator

  class MainCommand < Cli::Supercommand
    command "i", aliased: "init"

    class Init < Cli::Command
      class Options
        arg "type", desc: "app, spa, api", required: true
        arg "name", desc: "name of project", required: true
      end

      def run
        generator = ::Generator.new(args.name, "./#{args.name}")
        generator.generate args.type
      end
    end
  end
end
