require "teeplate"

module Kemalyst::Generator
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"

    @name : String
    @database : String
    @language : String

    def initialize(@name, @database = "pg", @language = "slang")
    end
  end
end
