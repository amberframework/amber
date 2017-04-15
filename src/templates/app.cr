require "teeplate"

module Kemalyst::Generator
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"

    @name : String
    @database : String
    @language : String

    def initialize(@name, @database = "pg", @language = "slang")
    end

    def filter(entry)
      puts "DRU: #{entry.path}"
      return entry.path.includes?("src/views") && !entry.path.includes?("#{@language}")
    end
  end
end
