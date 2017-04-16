require "../../templates/template"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "i", aliased: "init"

    class Init < Cli::Command
      class Options
        arg "type", desc: "app, api, spa", required: true
        arg "name", desc: "name of project", required: true
        string "-d", desc: "database", any_of: %w(pg mysql sqlite), default: "pg"
        string "-t", desc: "template language", any_of: %w(slang ecr), default: "slang"
      end

      def run
        name = File.basename(args.name)
        database = options.d? == "mysql" ? "mysql" : "pg"
        language = options.t? == "ecr" ? "ecr" : "slang"
        template = Template.new(name, "./#{args.name}", database: database, language: language)
        template.generate args.type
      end
    end
  end
end
