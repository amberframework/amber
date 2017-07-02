require "teeplate"

module Amber::CMD
  class WebSocket < Teeplate::FileTree
    directory "#{__DIR__}/socket"

    @name : String
    @fields : Array(String)

    def initialize(@name, @fields)

    end
  end
end
