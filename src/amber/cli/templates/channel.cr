module Amber::CLI
  class WebSocketChannel < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/channel"
    @name : String

    def initialize(@name)
      add_dependencies <<-DEPENDENCY
      require "../src/channels/**"
      DEPENDENCY
    end
  end
end
