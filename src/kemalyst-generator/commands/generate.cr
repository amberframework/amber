require "../../templates/template"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "g", aliased: "generate"

    REL_TEMPLATES_PATH = ["lib", "kemalyst-generator", "src", "templates"]

    class Generate < Cli::Command

      class Options
        arg "type", desc: "resource", required: true,
            any_of: %w(controller model view)
        arg "name", desc: "name of resource", required: true
      end

      def run

        # jump from ${project_path}/lib/kemalyst-generator/src/kemalyst-generator/commands
        # to ${project_path}
        path = File.expand_path("#{__DIR__}/../../../../../")

        # at least if an error occures the folder is under control
        if !Dir.exists?( File.join(path, ".git") )
          error! "Not running in a project directory : no git repository found"
        end

        templates_path = File.join([path] + REL_TEMPLATES_PATH)

        template = Template.new(args.name, path, templates_path)
        template.generate args.type
      end
    end
  end
end
