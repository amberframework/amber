module Amber::Environment
  class LoggerBuilder
    getter logger : Logger

    def self.logger(io, logging)
      new(io, logging).logger
    end

    def initialize(logger_io, logging)
      Colorize.enabled = logging.colorize
      @logger = Logger.new(logger_io)
      @logger.level = logging.severity
      @logger.progname = "Server"
      @logger.color = logging.color
      @logger.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
        io << datetime.to_s("%I:%M:%S")
        io << " "
        io << progname
        io << " (#{severity})" if severity > Logger::DEBUG
        io << " "
        io << message
      end
    end
  end
end
