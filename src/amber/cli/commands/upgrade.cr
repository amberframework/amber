module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "u", aliased: "upgrade"

    class New < Command
      class Options
        arg "version", desc: "version of Amber to use (i.e. v0.9.0, v0.10.0)", required: false
        help
      end

      class Help
        header "Upgrades the current Amber installation"
        caption "# Upgrades the current Amber installation"
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

        if (options.version? != nil)
          template = Amber::Recipes::Recipe.new(version, "./#{args.version}")
        else
          template = Template.new(version, "./#{args.version}")
        end

        # Encrypts production.yml by default.
        cwd = Dir.current; Dir.cd(args.name)
        # check for access, required tools
        # make a copy of the current amber bin/s
        # fork the copy
        # run sub command to wget new install tar.gz
        # make build
        # make install
        # make distclean
        Dir.cd(cwd)
      end
    end
  end
end
