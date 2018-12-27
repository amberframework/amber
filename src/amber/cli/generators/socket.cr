module Amber::CLI
  class WebSocket < Generator
    directory "#{__DIR__}/../templates/socket"

    def initialize(name, fields)
      super(name, fields)
    end

    def pre_render(directory)
      add_dependencies
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/sockets/**"
      DEPENDENCY
    end
  end
end
