require "../version"
require "cli"
require "./commands/**"
require "./templates/template"

AMBER_YML = ".amber.yml"

class Cli::Command
  def colorize(text, color)
    text.colorize(color).toggle(!options.no_color?).to_s
  end

  def colorize(text, color, mode)
    text.colorize(color).toggle(!options.no_color?).mode(mode).to_s
  end
end

module Amber::CLI
  include Amber::Environment
end
