require "teeplate"

module Amber::CMD
  class WebSocketChannel < Teeplate::FileTree
    directory "#{__DIR__}/channel"
    @name : String
    def initialize(@name)

    end
  end
end
