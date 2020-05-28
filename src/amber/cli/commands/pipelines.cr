require "cli"
require "shell-table"
require "../helpers/sentry"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    class Pipelines < Command
      getter result = Array(NamedTuple(pipes: Array(String), plugs: Array(String))).new
      property current_pipe : String?

      class Options
        bool "--no-color", desc: "disable colored output", default: false
        bool "--no-plugs", desc: "don't output the plugs", default: false
        help
      end

      class BadRoutesException < Exception
      end

      ROUTES_PATH          = "config/routes.cr"
      LABELS               = %w(Pipeline Pipe)
      LABELS_WITHOUT_PLUGS = %w(Pipeline)

      PIPELINE_REGEX =
        /^
          \s*
          pipeline  # match pipeline
          \s+       # require at least one whitespace character after pipeline
          (
            (?:
              (?:
                \:(?:\w+)
                |
                \"(?:\w+)\"
              )
              (?:\,\s*)?
            )+
          )         # match and capture all contiguous words
        /x

      PLUG_REGEX =
        /^
          \s*
          plug        # match plug
          \s+         # require at least one whitespace character after plug
          (
            [\w:]+    # match at least one words with maybe a colon
          )?
          (?:
            [\.\s*\(] # until we reach ., spaces, or braces
          )?
        /x

      FAILED_TO_PARSE_ERROR = "Could not parse pipeline/plugs in #{ROUTES_PATH}"
      UNRECOGNIZED_OPTION   = "Unrecognized option"

      command_name "pipelines"

      def run
        CLI.toggle_colors(options.no_color?)
        parse_routes
        print_pipelines
      rescue ex : BadRoutesException
        error ex.message
        info "Good bye :("
        exit! error: true
      rescue ex
        error "Error: Not valid project root directory."
        info "Run `amber pipelines` in project root directory."
        info "Good bye :("
        exit! error: true
      end

      private def parse_routes
        lines = File.read_lines(ROUTES_PATH)

        lines.map(&.strip).each do |line|
          case line
          when .starts_with?("pipeline") then set_pipe(line)
          when .starts_with?("plug")     then set_plug(line)
          else
            # skip line
          end
        end
      end

      private def set_pipe(line)
        match = line.match(PIPELINE_REGEX)

        if match && (pipes = match[1])
          pipes = pipes.split(/,\s*/).map { |s| s.gsub(/[:\"]/, "") }
          result << {pipes: pipes, plugs: [] of String}
        else
          raise BadRoutesException.new(FAILED_TO_PARSE_ERROR)
        end
      end

      private def set_plug(line)
        match = line.match(PLUG_REGEX)

        if match && (plug = match[1]) && result.last
          result.last[:plugs] << plug
        else
          raise BadRoutesException.new(FAILED_TO_PARSE_ERROR)
        end
      end

      private def print_pipelines
        table = ShellTable.new

        table.labels = options.no_plugs? ? LABELS_WITHOUT_PLUGS : LABELS
        table.label_color = :light_red unless options.no_color?
        table.border_color = :dark_gray unless options.no_color?

        if options.no_plugs?
          result.map { |pipes_and_plugs| pipes_and_plugs[:pipes] }.flatten.uniq.each do |pipe|
            row = table.add_row
            row.add_column(pipe)
          end
        else
          result.each do |pipes_and_plugs|
            pipes_and_plugs[:pipes].each do |pipe|
              pipes_and_plugs[:plugs].each do |plug|
                row = table.add_row
                row.add_column(pipe)
                row.add_column(plug) unless options.no_plugs?
              end
            end
          end
        end

        puts "\n", table
      end
    end
  end
end
