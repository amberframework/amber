module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "i", aliased: "init"

    class Init < Cli::Command
      class Options
        arg "type", required: true, any_of: %w(app)
        arg "name", desc: "name of project", required: true
      end

      def run

        templates_path = ENV["KGEN_TEMPLATES"]?

        if !templates_path
          error! "Unable to find templates path, try to set KGEN_TEMPLATES"
        end

        path = `pwd`

        template = Template.new(args.name, path, templates_path)
        template.generate args.type
      end
    end
  end
end
