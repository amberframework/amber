require "cli"
require "shell-table"
require "sentry/sentry_command"

module Amber::CMD
  class MainCommand < Cli::Supercommand

    class Routes < Sentry::SentryCommand
      command_name "routes"
      getter routes : JSON::Any?

      class Help
        caption "# Print out all defined routes in match order, with names"
      end

      def run
        @routes = get_routes
        print_routes_table
      rescue
        puts "Error: Not valid project root directory.".colorize(:red)
        puts "Run `amber routes` in project root directory.".colorize(:light_blue)
        puts "Good bye :("
        exit 1
      end

      private def get_routes
        code = <<-CODE
          require "amber"
          require "./src/**"

          AMBER_CMD_PROCESS_ROUTES = true
          puts Amber::Server.routes.to_json
        CODE
        routes_json = `crystal eval #{code.gsub("\n", ";").inspect}`
        return JSON.parse(routes_json) unless routes_json.empty?
        puts "No routes defined!"
      end

      private def print_routes_table
        table = ShellTable.new
        table.labels = [
          "Verb", "Controller", "Action", "Pipeline", "Scope", "Resource"
        ]
        table.label_color = :light_red
        table.border_color = :dark_gray
        routes.not_nil!.each do |k, v|
          row = table.add_row
          JSON.parse(v.to_s).each do |col, val|
            row.add_column val.to_s
          end
        end
        puts table
        exit
      end
    end
  end
end
