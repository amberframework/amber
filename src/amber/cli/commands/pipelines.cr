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
        help
      end

      LABELS     = ["Pipe", "Plug"]
      PIPE_REGEX = /(pipeline)\s+\:(\w+)(?:,\s+\"([^\"]+)\")?/
      PLUG_REGEX = /(plug)\s+([\w:]+)?/

      command_name "pipelines"

      def run
        parse_routes
        print_pipelines
      rescue
        puts "Error: Not valid project root directory.".colorize(:red)
        puts "Run `amber pipelines` in project root directory.".colorize(:light_blue)
        puts "Good bye :("
        exit 1
      end

      private def parse_routes
        lines = File.read_lines("config/routes.cr")
        lines = lines.map { |line| line.strip }
        lines.each do |line|
          case line
          when .starts_with?("pipeline")
            set_pipe(line)
          when .starts_with?("plug")
            set_plug(line)
          end
        end
      end

      private def set_pipe(line)
        match = line.match(PIPE_REGEX)
        if match
          @current_pipe = match[2]

          if @current_pipe
            result[@current_pipe] = [] of String
          end
        end
      end

      private def set_plug(line)
        match = line.match(PLUG_REGEX)
        if match
          plug = match[2]

          if @current_pipe
            result[@current_pipe] << plug
          end
        end
      end

      private def print_pipelines
        table = ShellTable.new

        table.labels = LABELS
        table.label_color = :light_red unless options.no_color?
        table.border_color = :dark_gray unless options.no_color?

        result.each do |pipe, plugs|
          row = table.add_row
          row.add_column(pipe)
          row.add_column("")

          plugs.each do |plug|
            row = table.add_row
            row.add_column("")
            row.add_column(plug)
          end
        end
        puts "\n", table
      end
    end
  end
end
