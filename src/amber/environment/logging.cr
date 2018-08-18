module Amber::Environment
  class Logging
    alias OptionsType = Hash(String, String | Bool | Array(String?))

    SEVERITY_MAP = {
      "debug":   Logger::DEBUG,
      "info":    Logger::INFO,
      "warn":    Logger::WARN,
      "error":   Logger::ERROR,
      "fatal":   Logger::FATAL,
      "unknown": Logger::UNKNOWN,
    }

    COLOR_MAP = {
      "black":         :black,
      "red":           :red,
      "green":         :green,
      "yellow":        :yellow,
      "blue":          :blue,
      "magenta":       :magenta,
      "cyan":          :cyan,
      "light_gray":    :light_gray,
      "dark_gray":     :dark_gray,
      "light_red":     :light_red,
      "light_green":   :light_green,
      "light_yellow":  :light_yellow,
      "light_blue":    :light_blue,
      "light_magenta": :light_magenta,
      "light_cyan":    :light_cyan,
      "white":         :white,
    }

    DEFAULTS = {
      "severity" => "debug",
      "colorize" => true,
      "color"    => "light_cyan",
      "filter"   => ["password", "confirm_password"] of String?,
      "skip"     => [] of String?,
      "context"  => ["request", "headers", "cookies", "session", "params"] of String?,
    }

    setter severity : String,
      color : String

    property colorize : Bool,
      context : Array(String?),
      skip : Array(String?),
      filter : Array(String?)

    def initialize(initial_logging : OptionsType)
      logging = DEFAULTS.merge(initial_logging)
      @colorize = logging["colorize"].as(Bool)
      @color = logging["color"].as(String)
      @severity = logging["severity"].as(String)
      @filter = logging["filter"].as(Array(String?))
      @skip = logging["skip"].as(Array(String?))
      @context = logging["context"].as(Array(String?))
    end

    def severity : Logger::Severity
      SEVERITY_MAP[@severity]
    end

    def color : Symbol
      COLOR_MAP[@color]
    end
  end
end
