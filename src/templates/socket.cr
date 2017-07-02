require "teeplate"
# require "./field.cr"

module Amber::CMD
  class WebSocket < Teeplate::FileTree
    directory "#{__DIR__}/socket"

    @name : String

    def initialize(@name)

    end

  end
end
