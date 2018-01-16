require "logger"
require "colorize"

module Amber::Environment
  class Logger < ::Logger
    {% for name in Severity.constants %}
      def {{name.id.downcase}}(message, progname = progname, color = :light_cyan)
        log(Severity::{{name.id}}, message, progname.ljust(10), color)
      end
    {% end %}

    def log(severity, message, progname = nil, color = :light_cyan)
      return if severity < level || !@io
      write(severity, Time.now, "#{progname || @progname} |".colorize(color).to_s, message)
    end
  end
end
