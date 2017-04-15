require "../../templates/template"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "i", aliased: "init"

    class Init < Cli::Command
      class Options
        arg "type", desc: "app, spa, api", required: true
        arg "name", desc: "name of project", required: true
        string "--db", desc: "type of database", any_of: %w(pg mysql sqlite), default: "pg"
      end

      def run
        name = File.basename(args.name)
        database = options.db? == "mysql" ? "mysql" : "pg"
        template = Template.new(name, "./#{args.name}", database: database)
        template.generate args.type
      end
    end
  end
end
