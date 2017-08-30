require "teeplate"

module Amber::CLI
  class WebSocketChannel < Teeplate::FileTree
    directory "#{__DIR__}/channel"
    @name : String

    def initialize(@name)
    end
  end
end
