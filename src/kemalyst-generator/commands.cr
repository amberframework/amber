require "./version"
require "./commands/*"

module Kemalyst::Generator
  class MainCommand < Cli::Supercommand
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
