module Amber::CLI
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"
    getter database_name_base

    @name : String
    @database : String
    @database_name_base : String
    @language : String
    @model : String
    @db_url : String
    @wait_for : String

    def initialize(@name, @database = "pg", @language = "slang", @model = "granite")
      @db_url = ""
      @wait_for = ""
      @database_name_base = generate_database_name_base
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end

    private def generate_database_name_base
      @name.gsub('-', '_')
    end
  end
end
