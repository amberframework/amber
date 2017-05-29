AMBER_YML    = ".amber.yml"
DATABASE_YML = "config/database.yml"

require "./version"
require "./commands/*"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command_name "amber"
    version VERSION

    class Help
      header "Amber CMD"
    end

    class Options
      version
      help
    end
  end
end
