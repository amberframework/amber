module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "g", aliased: "generate"

    class Generate < Cli::Command
      class Options
        arg "type", desc: "resource", required: true
        arg "name", desc: "name of resource", required: true
      end

      def run
        template = Template.new(args.name, ".")
        template.generate args.type
      end
    end
  end
end
