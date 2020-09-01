require "../version"
require "cli"
require "./recipes/recipe"
require "./config"
require "./commands/command"
require "./commands/*"

module Launch::CLI
  include Launch::Environment
  LAUNCH_YML = ".launch.yml"

  def self.toggle_colors(on_off)
    Colorize.enabled = !on_off
  end

  class MainCommand < ::Cli::Supercommand
    command_name "launch"
    version "Launch CLI (launchframework.org) - v#{VERSION}"

    class Help
      title "\nLaunch CLI"
      header <<-EOS
        The `launch new` command creates a new Launch application with a default
        directory structure and configuration at the path you specify.

        You can specify extra command-line arguments to be used every time
        `launch new` runs in the .launch.yml configuration file in your project
        root directory

        Note that the arguments specified in the .launch.yml file does not affect the
        defaults values shown above in this help message.

        Usage:
        launch new [app_name] -d [pg | mysql | sqlite] -t [slang | ecr] --no-deps --minimal
      EOS

      footer <<-EOS
      Example:
        launch new ~/Code/Projects/weblog
        This generates a skeletal Launch installation in ~/Code/Projects/weblog.
      EOS
    end

    class Options
      version desc: "prints Launch version"
      help desc: "describe available commands and usages"
      string ["-t", "--template"], desc: "preconfigure for selected template engine", any_of: %w(slang ecr), default: "ecr"
      string ["-d", "--database"], desc: "preconfigure for selected database.", any_of: %w(pg mysql sqlite), default: "sqlite"
      string ["-r", "--recipe"], desc: "use a named recipe. See documentation at https://docs.launchframework.org/launch/cli/recipes.", default: nil
    end
  end
end
