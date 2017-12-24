require "logger"
require "colorize"

module Amber::Environment
  class Logger < ::Logger
    def puts(message, progname = progname, color = :magenta)
      log(self.level, message, "#{progname}\t|".colorize(color))
    end

    {% for name in Severity.constants %}
      def {{name.id.downcase}}(message, color = :light_cyan)
        log(Severity::{{name.id}}, message, "#{progname}\t|".colorize(color))
      end
    {% end %}
  end

  class LoggerBuilder
    def self.logger(io, logging)
      new(io, logging).logger
    end

    def initialize(io, logging)
      Colorize.enabled = logging.color
      @logger = Environment::Logger.new(io)
      @logger.level = logging.severity
      @logger.progname = "Server"
      @logger.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
        io << datetime.to_s("%I:%M:%S")
        io << " (#{severity}) "
        io << progname
        io << " "
        io << message
      end
    end

    def logger
      @logger
    end
  end

end