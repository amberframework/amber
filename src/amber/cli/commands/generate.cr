module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "g", aliased: "generate"

    class Generate < ::Cli::Command
      class Options
        arg "type", desc: "scaffold, model, controller, migration, mailer, socket, channel, auth", required: true
        arg "name", desc: "name of resource", required: true
        arg_array "fields", desc: "user:reference name:string body:text age:integer published:bool"
        bool "--no-color", desc: "Disable colored output", default: false
      end

      def run
        template = Template.new(args.name, ".", args.fields)
        template.generate args.type
      end

      class Help
        caption "# Generate Amber classes"
      end
    end
  end
end
