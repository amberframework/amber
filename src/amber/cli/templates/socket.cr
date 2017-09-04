module Amber::CLI
  class WebSocket < Teeplate::FileTree
    directory "#{__DIR__}/socket"

    @name : String
    @fields : Array(String)

    def initialize(@name, @fields)
    end
  end
end
