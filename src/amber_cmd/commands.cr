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
