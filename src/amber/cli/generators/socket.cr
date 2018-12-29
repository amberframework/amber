module Amber::CLI
  class WebSocket < Generator
    directory "#{__DIR__}/../templates/socket"
    getter channels : Array(String)

    def initialize(name, @channels)
      super(name, nil)
    end

    def pre_render(directory)
      add_dependencies
    end

    def post_render(directory)
      channels.each do |channel|
        WebSocketChannel.new(channel, nil).render(directory)
      end
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/sockets/**"
      DEPENDENCY
    end
  end
end
