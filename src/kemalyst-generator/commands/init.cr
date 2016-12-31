require "../../templates/template"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "i", aliased: "init"

    class Init < Cli::Command
      class Options
        arg "type", desc: "app, spa, api", required: true
        arg "name", desc: "name of project", required: true
      end

      def run
        template = Template.new(args.name, "./#{args.name}")
        template.generate args.type
      end
    end
  end
end
