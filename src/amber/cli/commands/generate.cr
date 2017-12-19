module Amber::CLI
  class_property color = true

  class MainCommand < ::Cli::Supercommand
    command "g", aliased: "generate"

    class Generate < Command
      class Options
        arg "type", desc: "scaffold, model, controller, migration, mailer, socket, channel, auth, error", required: true
        arg "name", desc: "name of resource", required: false
        arg_array "fields", desc: "user:reference name:string body:text age:integer published:bool"
        bool "--no-color", desc: "Disable colored output", default: false
        help
      end

      def run
        if args.type == "error"
          template = Template.new("error", ".")
        else
          ensure_name_argument!
          template = Template.new(args.name, ".", args.fields)
        end
        template.generate args.type
      end

      private def ensure_name_argument!
        unless args.name?
          CLI.logger.puts "Parsing Error: The NAME argument is required.", "Error", :red
          exit! help: true, error: true
        end
      end

      class Help
        caption "# Generate Amber classes"
      end
    end
  end
end
