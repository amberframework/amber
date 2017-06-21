AMBER_YML    = ".amber.yml"
DATABASE_YML = "config/database.yml"

require "./version"
require "./commands/*"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command_name "amber"
    version "Amber CMD (ambercr.io) - v#{VERSION}"

    class Help
      title "\nAmber - Command Line Interface"
      header <<-EOS
        The `amber new` command creates a new Amber application with a default
        directory structure and configuration at the path you specify.

        You can specify extra command-line arguments to be used every time
        `amber new` runs in the .amber.yml configuration file in your project
        root directory

        Note that the arguments specified in the .amber.yml file does not affect the
        defaults values shown above in this help message.

        Usage:
        amber new [app_name] -d [pg | mysql | sqlite] -t [slang | ecr] --deps
        EOS

      footer <<-EOS
      Example:
        amber new ~/Code/Projects/weblog
        This generates a skeletal Amber installation in ~/Code/Projects/weblog.
      EOS
    end

    class Options
      version desc: "# Prints Amber version"
      help desc: "# Describe available commands and usages"
      string ["-t", "--template"], desc: "# Preconfigure for selected template engine. Options: slang | ecr", default: "slang"
      string ["-d", "--database"], desc: "# Preconfigure for selected database. Options: pg | mysql | sqlite", default: "pg"
    end
  end
end
