module Amber::Environment
  class Logging
    alias OptionsType = NamedTuple(
      severity: String,
      colorize: Bool,
      filter: Array(String?),
      skip: Array(String?),
      context: Array(String?))

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

    def initialize(logging : OptionsType)
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
