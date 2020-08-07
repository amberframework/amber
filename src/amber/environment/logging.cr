module Amber::Environment
  class Logging
    alias OptionsType = Hash(String, String | Bool | Array(String))

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
      "filter"   => ["password", "confirm_password"],
      "skip"     => [] of String,
    }

    setter color : String,
      severity : (String | Symbol)

    property colorize : Bool,
      skip : Array(String),
      filter : Array(String)

    def initialize(initial_logging : OptionsType)
      logging = DEFAULTS.merge(initial_logging)
      @colorize = logging["colorize"].as(Bool)
      @color = logging["color"].as(String)
      @severity = logging["severity"].as(String)
      @filter = logging["filter"].as(Array(String))
      @skip = logging["skip"].as(Array(String))
    end

    def color : Symbol
      COLOR_MAP[@color]
    end

    def severity : Log::Severity
      Log::Severity.parse @severity.to_s
    end
  end
end
