require "../../templates/template"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command "i", aliased: "init"

    class Init < Cli::Command
      class Options
        bool "--deps", desc: "installs deps, (shards update)", default: false
        arg "type", desc: "app, spa, api", required: true
        arg "name", desc: "name of project", required: true
        string "--db", desc: "type of database", any_of: %w(pg mysql sqlite), default: "pg"
      end

      def run
        name = File.basename(args.name)
        template = Template.new(name, "./#{args.name}")
        template.generate(args.type, options)
      end
    end
  end
end
