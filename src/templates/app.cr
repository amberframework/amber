require "teeplate"

module Kemalyst::Generator
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"

    @name : String
    @database : String

    def initialize(@name, @database = "pg", @language = "slang")
    end

    def filter(entry)
      return entry.path.includes?("src/views") && !entry.path.includes?("#{@language}")
    end
  end
end
