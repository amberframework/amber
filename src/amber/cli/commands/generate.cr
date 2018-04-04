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

      class Help
        header "Generates application based on templates"
        caption "# Generates application based on templates"
      end

      def run
        if args.type == "error"
          template = Template.new("error", ".")
        else
          ensure_name_argument!
          # if the app was generated from a recipe and the component can be
          # generated for the recipe then use the recipe generator
          if recipe && recipe != "none" && Amber::Recipes::Recipe.can_generate?(args.type, recipe)
            template = Amber::Recipes::Recipe.new(args.name, ".", recipe, args.fields)
          else
            # otherwise use the standard template generator
            template = Template.new(args.name, ".", args.fields)
          end
        end
        template.generate args.type
      end

      def recipe
        CLI.config.recipe
      end

      private def ensure_name_argument!
        unless args.name?
          CLI.logger.info "Parsing Error: The NAME argument is required.", "Error", :red
          exit! help: true, error: true
        end
      end

      class Help
        caption "# Generate Amber classes"
      end
    end
  end
end
