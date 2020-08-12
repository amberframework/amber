require "../plugins/plugin"

module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "pl", aliased: "plugin"

    class Plugin < Command
      class Options
        arg "action", desc: "install or uninstall", required: true
        arg "name", desc: "name of the shard", required: true
        help
      end

      class Help
        header "Generates the named plugin from the given plugin template"
        caption "Generates application plugin based on templates"
      end

      def run
        ensure_action_argument!
        ensure_name_argument!

        if Amber::Plugins::Plugin.can_generate?(args.name)
          template = Amber::Plugins::Plugin.new(args.name, "./src/plugins")
          template.generate args.action
        end
      end

      private def ensure_name_argument!
        unless args.name?
          error "Parsing Error: The NAME argument is required."
          exit! help: true, error: true
        end
      end

      private def ensure_action_argument!
        if args.action != "install"
          error "Invalid plugin action, 'install' is the only supported action currently."
          exit! help: true, error: true
        end
      end
    end
  end
end
