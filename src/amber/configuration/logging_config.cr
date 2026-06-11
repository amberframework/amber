require "yaml"

module Amber::Configuration
  class LoggingConfig
    include YAML::Serializable

    property severity : String = "debug"
    property colorize : Bool = true
    property color : String = "light_cyan"
    property filter : Array(String) = ["password", "confirm_password"]
    property skip : Array(String) = [] of String

    def initialize
    end

    def severity_level : Log::Severity
      Log::Severity.parse(@severity)
    end

    def color_symbol : Symbol
      Amber::Environment::Logging::COLOR_MAP.fetch(@color, :light_cyan)
    end

    def validate! : Nil
      valid_severities = ["trace", "debug", "info", "notice", "warn", "error", "fatal", "none"]
      unless valid_severities.includes?(@severity.downcase)
        raise Amber::Exceptions::ConfigurationError.new(
          "logging.severity must be one of #{valid_severities.join(", ")}, got '#{@severity}'"
        )
      end
    end
  end
end
