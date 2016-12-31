require "teeplate"

module Kemalyst::Generator
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"

    @name : String

    def initialize(@name)
    end
  end
end
