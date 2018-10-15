require "logger"
require "colorize"

module Amber::Environment
  class Logger < ::Logger
    property color : Symbol = :light_cyan

    {% for name in Severity.constants %}
      def {{name.id.downcase}}(message, progname = progname, color = @color)
        log(Severity::{{name.id}}, message, progname.ljust(10), color)
      end
    {% end %}

    def log(severity, message, progname = nil, color = @color)
      return if severity < level || !@io
      write(severity, Time.now, "#{progname || @progname} |".colorize(color).to_s, message)
    end
  end
end
