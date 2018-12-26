module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "n", aliased: "new"

    class New < Command
      class Options
        arg "name", desc: "name/path of project", required: true
        string "-d", desc: "Select the database database engine", any_of: %w(pg mysql sqlite), default: "pg"
        bool "--deps", desc: "Installs project dependencies, this is the equivalent of running (shards update)", default: false
        string "-m", desc: "Select the model type", any_of: %w(granite crecto), default: "granite"
        bool "--no-color", desc: "Disable colored output", default: false
        string "-t", desc: "Selects the template engine language", any_of: %w(slang ecr), default: "slang"
        string "-r", desc: "Use a named recipe. See documentation at https://docs.amberframework.org/amber/cli/recipes.", default: nil
        help
      end

      class Help
        header "Generates a new Amber project"
        caption "# Generates a new Amber project"
      end

      def run
        CLI.toggle_colors(options.no_color?)
        full_path_name = File.join(Dir.current, args.name)
        if full_path_name =~ /\s+/
          error "Path and project name can't contain a space."
          info "Replace spaces with underscores or dashes."
          info "#{full_path_name} should be #{full_path_name.gsub(/\s+/, "_")}"
          exit! error: true
        end
        name = File.basename(args.name)

        if (options.r? != nil)
          template = Amber::Recipes::Recipe.new(name, "./#{args.name}", "#{options.r}")
        else
          template = Template.new(name, "./#{args.name}")
        end
        template.generate("app", options)

        # Encrypts production.yml by default.
        cwd = Dir.current; Dir.cd(args.name)
        MainCommand.run ["encrypt", "production", "--noedit"]
        Dir.cd(cwd)
      end
    end
  end
end
