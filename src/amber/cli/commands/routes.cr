require "cli"
require "shell-table"
require "../helpers/sentry"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    class Routes < Command
      RESOURCE_ROUTE_REGEX = /(\w+)\s+\"([^\"]+)\",\s*([\w:]+)(?:,\s*(\w+)\:\s*\[([^\]]+)\])?/
      VERB_ROUTE_REGEX     = /(\w+)\s+\"([^\"]+)\",\s*([\w:]+),\s*:(\w+)/
      WEBSOCKET_ROUTE_REGEX= /(websocket)\s+\"([^\"]+)\",\s*([\w:]+)/
      PIPE_SCOPE_REGEX     = /(routes)\s+\:(\w+)(?:,\s+\"([^\"]+)\")?/

      LABELS         = ["Verb", "Controller", "Action", "Pipeline", "Scope", "URI Pattern"]
      ACTION_MAPPING = {
        "get" => ["index", "show", "new", "edit"],
        "post" => ["create"], "patch" => ["update"],
        "put" => ["update"], "delete" => ["destroy"],
      }

      command_name "routes"
      getter routes = Array(Hash(String, String)).new
      property current_pipe : String?
      property current_scope : String?

      class Help
        header "Prints all defined application routes"
        caption "# Prints all defined application routes"
      end

      class Options
        bool "--no-color", desc: "Disable colored output", default: false
        help
      end

      def run
        parse_routes
        print_routes_table
      rescue
        puts "Error: Not valid project root directory.".colorize(:red)
        puts "Run `amber routes` in project root directory.".colorize(:light_blue)
        puts "Good bye :("
        exit 1
      end

      private def parse_routes
        File.read_lines("config/routes.cr").each do |line|
          case line.strip
          when .starts_with?("routes")
            set_pipe(line)
          when .starts_with?("resources")
            set_resources(line)
          else
            set_route(line)
          end
        end
      end

      private def set_route(route_string)
        if route_match = route_string.to_s.match(VERB_ROUTE_REGEX)
          return unless ACTION_MAPPING.keys.includes?(route_match[1]?.to_s)
          build_route(route_match)
        elsif route_match = route_string.to_s.match(WEBSOCKET_ROUTE_REGEX)
          build_route(route_match)
        end
      end

      private def set_resources(resource_string)
        if route_match = resource_string.to_s.match(RESOURCE_ROUTE_REGEX)
          filter = route_match[4]?
          filter_actions = route_match[5]?.to_s.gsub(/\:|\s/, "").split(",")
          ACTION_MAPPING.each do |verb, v|
            v.each do |action|
              case filter
              when "only"
                next unless filter_actions.includes?(action)
              when "except"
                next if filter_actions.includes?(action)
              end
              build_route(
                verb: verb, controller: route_match[3]?, action: action,
                pipeline: current_pipe, scope: current_scope,
                uri_pattern: build_uri_pattern(route_match[2]?, action, current_scope)
              )
            end
          end
        end
      end

      def build_route(verb, uri_pattern, controller, action, pipeline, scope = "")
        route = {"Verb" => verb.to_s}
        route["URI Pattern"] = uri_pattern.to_s
        route["Controller"] = controller.to_s
        route["Action"] = action.to_s
        route["Pipeline"] = pipeline.to_s
        route["Scope"] = scope.to_s
        routes << route
      end

      private def build_route(route_match)
        build_route(
          verb: route_match[1]?, controller: route_match[3]?,
          action: route_match[4]? || "", pipeline: current_pipe,
          scope: current_scope, uri_pattern: route_match[2]?
        )
      end

      private def build_uri_pattern(route, action, scope)
        route_end = {"show" => ":id", "new" => "new", "edit" => ":id/edit", "update" => ":id", "destroy" => ":id"}
        [scope, route, route_end[action]?].compact.join("/").gsub("//", "/")
      end

      private def set_pipe(pipe_string)
        if route_match = pipe_string.to_s.match(PIPE_SCOPE_REGEX)
          @current_pipe = route_match[2]?
          @current_scope = route_match[3]?
        end
      end

      private def print_routes_table
        table = ShellTable.new
        table.labels = LABELS
        table.label_color = :light_red unless options.no_color?
        table.border_color = :dark_gray unless options.no_color?
        routes.each do |route|
          row = table.add_row
          LABELS.each do |l|
            row.add_column route[l].to_s
          end
        end
        puts "\n", table
      end
    end
  end
end
