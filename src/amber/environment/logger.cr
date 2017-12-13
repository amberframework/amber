require "logger"
require "colorize"

module Amber::Environment
  class Logger < ::Logger
    def puts(message, program = "Amber", color = :magenta)
      log(self.level, message, "#{program} |".colorize(color))
    end
  end
end
