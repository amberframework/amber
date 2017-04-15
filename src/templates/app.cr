require "teeplate"

module Kemalyst::Generator
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"

    @name : String
    @database : String

    def initialize(@name, @database = "pg")
    end
  end
end
