module Amber::CLI
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"

    @name : String
    @database : String
    @language : String
    @model : String
    @db_url : String
    @wait_for : String

    def initialize(@name, @database = "pg", @language = "slang", @model = "granite")
      @db_url = ""
      @wait_for = ""
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end
  end
end
