require "logger"
require "colorize"

module Amber::Environment
  class Logger < ::Logger
    def puts(message, progname = progname, color = :magenta)
      log(self.level, message, "#{progname} |".colorize(color))
    end

    {% for name in Severity.constants %}
      def {{name.id.downcase}}(message, color = :light_cyan)
        log(Severity::{{name.id}}, message, "#{progname} |".colorize(color))
      end
    {% end %}
  end
end
