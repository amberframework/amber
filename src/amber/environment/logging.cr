module Amber::Environment
  class Logging
    SEVERITY_MAP = {
      "debug":   Logger::DEBUG,
      "info":    Logger::INFO,
      "warn":    Logger::WARN,
      "error":   Logger::ERROR,
      "fatal":   Logger::FATAL,
      "unknown": Logger::UNKNOWN,
    }

    setter severity : String
    property colorize : Bool
    property context : Array(String?)
    property skip : Array(String?)
    property filter : Array(String?)

    def initialize(logging : Settings::LoggingType)
      @colorize = logging[:colorize]
      @severity = logging[:severity]
      @filter = logging[:filter]
      @skip = logging[:skip]
      @context = logging[:context]
    end

    def severity
      SEVERITY_MAP[@severity]
    end

    def logger
      @logger
    end
  end
end
