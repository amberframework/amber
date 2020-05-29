require "log"
require "colorize"

module Amber::Environment
  class Logger
    property color : Symbol = :light_cyan
    property level : (Log::Severity | String)
    property progname : String
    property formatter : Log::Formatter? = nil

    def initialize(@io : IO?,
                   @level = ENV.fetch("CRYSTAL_LOG_LEVEL", "INFO"),
                   @progname = ENV.fetch("CRYSTAL_LOG_SOURCES", ""),
                   @formatter = nil)
      builder : Log::Builder = Log.builder
      backend = Log::IOBackend.new(@io || STDOUT)
      backend.formatter = @formatter || default_format

      builder.clear
      level = Log::Severity.parse(@level.to_s)
      progname.split(',', remove_empty: false) do |source|
        source = source.strip
        builder.bind(source, level, backend)
      end
    end

    def default_format
      Log::Formatter.new do |entry, io|
        io << entry.timestamp.to_s("%I:%M:%S")
        io << " "
        io << entry.source
        io << " (#{entry.severity})" if entry.severity > Log::Severity::Debug
        io << " "
        io << entry.message
      end
    end

    {% for name in ["debug", "verbose", "info", "warn", "error", "fatal"] %}
      def {{name.id.downcase}}(message, progname = progname, color = @color)
        Log.{{name.id.downcase}} { "#{(progname || @progname).colorize(color).to_s} | #{message}"  }
      end
    {% end %}
  end
end
