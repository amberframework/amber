module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "n", aliased: "new"

    class New < Command
      class Options
        arg "name", desc: "name of project", required: true
        string "-d", desc: "database", any_of: %w(pg mysql sqlite), default: "pg"
        string "-t", desc: "template language", any_of: %w(slang ecr), default: "slang"
        string "-m", desc: "model type", any_of: %w(granite crecto), default: "granite"
        bool "--deps", desc: "installs deps, (shards update)", default: false
        bool "--no-color", desc: "Disable colored output", default: false
        help
      end

      class Help
        header "Generates a new Amber project"
        caption "# Generates a new Amber project"
      end

      def run
        Amber::CLI.color = !options.no_color?
        full_path_name = File.join(`pwd`.sub("\n", ""), args.name)
        if full_path_name.includes?(" ")
          puts "Error:  Path and project name can't contain a space. Underscores are fine though."
          puts "Error: #{full_path_name} should be #{full_path_name.gsub(/\s+/, "_")}"
          exit 1
        end
        name = File.basename(args.name)
        template = Template.new(name, "./#{args.name}")
        template.generate("app", options)

        # Encrypts production.yml by default.
        cwd = Dir.current; Dir.cd(args.name)
        MainCommand.run ["encrypt", "production", "--noedit"]
        Dir.cd(cwd)
      end
    end
  end
end
