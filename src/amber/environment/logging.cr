require "yaml"

module Amber::Environment
  class Logging
    include YAML::Serializable

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

    @[YAML::Field(key: "color")]
    setter color : String = "light_cyan"

    @[YAML::Field(key: "severity")]
    setter severity : String = "debug"

    @[YAML::Field(key: "colorize")]
    property colorize : Bool = true

    @[YAML::Field(key: "skip")]
    property skip : Array(String) = [] of String

    @[YAML::Field(key: "filter")]
    property filter : Array(String) = ["password", "confirm_password"]

    def initialize
    end

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
