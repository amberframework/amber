module Amber::CLI
  class WebSocket < Generator
    command :socket
    directory "#{__DIR__}/../templates/socket"

    def initialize(name, fields)
      super(name, fields)
    end

    def pre_render(directory, **args)
      add_dependencies
    end

    def post_render(directory, **args)
      fields.each do |field|
        WebSocketChannel.new(field.name, nil).render(directory)
      end
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/sockets/**"
      DEPENDENCY
    end
  end
end
