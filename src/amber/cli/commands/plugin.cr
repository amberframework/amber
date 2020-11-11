require "../plugins/plugin"

module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "pl", aliased: "plugin"

    class Plugin < Command
      class Options
        bool ["-u", "--uninstall"], desc: "uninstall plugin", default: false
        arg "name", desc: "name of the shard", required: true
        arg_array "args", desc: "args available during template rendering"
        help
      end

      class Help
        header "Generates the named plugin from the given plugin template"
        caption "Generates application plugin based on templates"
      end

      def run
        uninstall_plugin?
        ensure_name_argument!

        if Amber::Plugins::Plugin.can_generate?(args.name)
          template = Amber::Plugins::Plugin.new(args.name, "./src/plugins", options.args)
          template.generate (options.uninstall? ? "uninstall" : "install")
        end
      end

      private def ensure_name_argument!
        unless args.name?
          error "Parsing Error: The NAME argument is required."
          exit! error: true
        end
      end

      private def uninstall_plugin?
        if options.uninstall?
          error "Invalid plugin action, 'uninstalling' is currently not supported."
          exit! error: true
        end
      end
    end
  end
end
