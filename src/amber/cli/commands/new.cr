module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "n", aliased: "new"

    class New < Command
      class Options
        arg "name", desc: "name/path of project", required: true
        string "-d", desc: "Select the database database engine, can be one of: pg | mysql | sqlite", default: "pg"
        string "-t", desc: "Selects the template engine language, can be one of: slang | ecr", default: "slang"
        string "-r", desc: "Use a named recipe.  See documentation at  https://docs.amberframework.org/amber/cli/recipes.", default: nil
        bool "--no-color", desc: "Disable colored output", default: false
        bool ["-y", "--assume-yes"], desc: "Assume yes to disable interactive mode", default: false
        bool "--no-deps", desc: "Does not install dependencies, this avoids running shards update", default: false
        bool "--minimal", desc: "Does not install npm dependencies", default: false
        help
      end

      class Help
        header "Generates a new Amber project"
        caption "generates a new Amber project"
      end

      def run
        CLI.toggle_colors(options.no_color?)
        if args.name == "."
          name = File.basename(Dir.current)
          full_path_name = Dir.current
        else
          name = File.basename(args.name)
          full_path_name = File.join(Dir.current, args.name)
        end

        if full_path_name =~ /\s+/
          error "Path and project name can't contain a space."
          info "Replace spaces with underscores or dashes."
          info "#{full_path_name} should be #{full_path_name.gsub(/\s+/, "_")}"
          exit! error: true
        end
        if (options.r? != nil)
          generator = Amber::Recipes::Recipe.new(name, full_path_name, "#{options.r}")
        else
          generator = Generators.new(name, full_path_name)
        end
        generator.generate_app(options)

        # Encrypts production.yml by default.
        cwd = Dir.current; Dir.cd(full_path_name)
        MainCommand.run ["encrypt", "production", "--noedit"]
        Dir.cd(cwd)
      end
    end
  end
end
