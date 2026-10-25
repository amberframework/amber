module Amber::Support
  # Colors Amber's own log output according to the `logging.colorize` setting.
  #
  # Amber leaves the process-wide `Colorize.enabled` flag to the app, so
  # `colorize: false` turns color off for Amber's lines only. When the app has
  # disabled `Colorize` itself (for example through `NO_COLOR`), Amber's lines
  # stay plain whatever the setting says.
  #
  # ```
  # Amber::Support::LogColor.paint("ready", :green, enabled: false).to_s # => "ready"
  # ```
  module LogColor
    def self.paint(value, color : Symbol, enabled : Bool)
      colored = value.colorize(color)
      enabled ? colored : colored.toggle(false)
    end
  end
end
