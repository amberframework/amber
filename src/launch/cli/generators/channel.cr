require "./generator"

module Launch::CLI
  class WebSocketChannel < Generator
    command :channel
    directory "#{__DIR__}/../templates/channel"

    def initialize(name, fields)
      super(name, fields)
    end

    def pre_render(directory, **args)
      add_dependencies
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/channels/**"
      DEPENDENCY
    end
  end
end
