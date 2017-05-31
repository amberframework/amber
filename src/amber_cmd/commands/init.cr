require "../../templates/template"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "n", aliased: "new"

    class New < Cli::Command
      class Options
        arg "name", desc: "name of project", required: true
        string "-d", desc: "database", any_of: %w(pg mysql sqlite), default: "pg"
        string "-t", desc: "template language", any_of: %w(slang ecr), default: "slang"
        bool "--deps", desc: "installs deps, (shards update)", default: false
      end

      def run
        name = File.basename(args.name)
        template = Template.new(name, "./#{args.name}")
        template.generate("app", options)
      end
    end
  end
end
