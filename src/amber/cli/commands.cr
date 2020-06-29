require "../version"
require "cli"
require "./recipes/recipe"
require "./config"
require "./commands/command"
require "./commands/*"

module Amber::CLI
  include Amber::Environment
  AMBER_YML = ".amber.yml"

  def self.toggle_colors(on_off)
    Colorize.enabled = !on_off
  end

  class MainCommand < ::Cli::Supercommand
    command_name "amber"
    version "Amber CLI (amberframework.org) - v#{VERSION}"

    class Help
      title "\nAmber CLI"
      header <<-EOS
        The `amber new` command creates a new Amber application with a default
        directory structure and configuration at the path you specify.

        You can specify extra command-line arguments to be used every time
        `amber new` runs in the .amber.yml configuration file in your project
        root directory

        Note that the arguments specified in the .amber.yml file does not affect the
        defaults values shown above in this help message.

        Usage:
        amber new [app_name] -d [pg | mysql | sqlite] -t [slang | ecr] --no-deps --minimal
      EOS

      footer <<-EOS
      Example:
        amber new ~/Code/Projects/weblog
        This generates a skeletal Amber installation in ~/Code/Projects/weblog.
      EOS
    end

    class Options
      version desc: "prints Amber version"
      help desc: "describe available commands and usages"
      string ["-t", "--template"], desc: "preconfigure for selected template engine", any_of: %w(slang ecr), default: "slang"
      string ["-d", "--database"], desc: "preconfigure for selected database.", any_of: %w(pg mysql sqlite), default: "pg"
      string ["-r", "--recipe"], desc: "use a named recipe. See documentation at https://docs.amberframework.org/amber/cli/recipes.", default: nil
    end
  end
end
