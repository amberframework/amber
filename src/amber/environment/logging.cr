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

    DEFAULTS = {
      severity: "debug",
      colorize: true,
      filter:   ["password", "confirm_password"] of String?,
      skip:     [] of String?,
      context:  ["request", "headers", "cookies", "session", "params"] of String?,
    }

    setter severity : String
    property colorize : Bool,
      context : Array(String?),
      skip : Array(String?),
      filter : Array(String?)

    def initialize(logging : OptionsType)
      @colorize = logging[:colorize]
      @severity = logging[:severity]
      @filter = logging[:filter]
      @skip = logging[:skip]
      @context = logging[:context]
    end

    def severity : Logger::Severity
      SEVERITY_MAP[@severity]
    end
  end
end
