require "cli"
require "shell-table"
require "../helpers/sentry"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    class Pipelines < Command
      getter result = Hash(String?, Array(String)).new
      property current_pipe : String?

      class Options
        bool "--no-color", desc: "Disable colored output", default: false
        bool "--no-plugs", desc: "Don't output the plugs", default: false
        help
      end

      class BadRoutesException < Exception
      end

      ROUTES_PATH          = "config/routes.cr"
      LABELS               = %w(Pipe Plug)
      LABELS_WITHOUT_PLUGS = %w(Pipe)

      PIPE_REGEX = /(pipeline)\s+\:(\w+)(?:,\s+\"([^\"]+)\")?/
      PLUG_REGEX = /(plug)\s+([\w:]+)?/

      FAILED_TO_PARSE_ERROR = "Could not parse pipeline/plugs in #{ROUTES_PATH}"

      command_name "pipelines"

      def run
        parse_routes
        print_pipelines
      rescue ex : BadRoutesException
        CLI.logger.error(ex.message.colorize(:red))
        CLI.logger.error "Good bye :("
        exit 1
      rescue
        CLI.logger.error "Error: Not valid project root directory.".colorize(:red)
        CLI.logger.error "Run `amber pipelines` in project root directory.".colorize(:light_blue)
        CLI.logger.error "Good bye :("
        exit 1
      end

      private def parse_routes
        lines = File.read_lines(ROUTES_PATH)

        lines.map(&.strip).each do |line|
          case line
          when .starts_with?("pipeline")
            set_pipe(line)
          when .starts_with?("plug")
            set_plug(line)
          end
        end
      end

      private def set_pipe(line)
        if ((match = line.match(PIPE_REGEX)) && (@current_pipe = match[2]))
          result[@current_pipe] = [] of String
        else
          raise BadRoutesException.new(FAILED_TO_PARSE_ERROR)
        end
      end

      private def set_plug(line)
        if (match = line.match(PLUG_REGEX)) && (plug = match[2]) && @current_pipe
          result[@current_pipe] << plug
        else
          raise BadRoutesException.new(FAILED_TO_PARSE_ERROR)
        end
      end

      private def print_pipelines
        table = ShellTable.new

        table.labels = options.no_plugs? ? LABELS_WITHOUT_PLUGS : LABELS
        table.label_color = :light_red unless options.no_color?
        table.border_color = :dark_gray unless options.no_color?

        result.each do |pipe, plugs|
          row = table.add_row
          row.add_column(pipe)
          row.add_column("") unless options.no_plugs?

          unless options.no_plugs?
            plugs.each do |plug|
              row = table.add_row
              row.add_column("")
              row.add_column(plug)
            end
          end
        end
        puts "\n", table
      end
    end
  end
end
