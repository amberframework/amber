require "./version"
require "./commands/*"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
    command_name "kgen"
    version VERSION

    class Help
      header "Kemalyst Generator"
    end

    class Options
      version
      help
    end
  end
end
