require "../plugins/plugin"

module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "pl", aliased: "plugin"

    class Plugin < Command
      class Options
        arg "action", desc: "add sub command", required: true
        arg "name", desc: "name/path/github_repo of plugin", required: true
        help
      end

      class Help
        header "Generates the named plugin from the given plugin template"
        caption "Generates application plugin based on templates"
      end

      def run
        if args.action != "add"
          error "Invalid plugin action, only 'add' is allowed."
          exit! help: true, error: true
        end

        ensure_name_argument!
        if Amber::Plugins::Plugin.can_generate?(args.name)
          template = Amber::Plugins::Plugin.new(args.name, ".")
          template.generate args.action
        end
      end

      private def ensure_name_argument!
        unless args.name?
          error "Parsing Error: The NAME argument is required."
          exit! help: true, error: true
        end
      end
    end
  end
end
