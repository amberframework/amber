require "../field.cr"

module Amber::CLI::Scaffold
  class View < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/view"

    @name : String
    @fields : Array(Field)
    @language : String
    @database : String
    @model : String

    def initialize(@name, fields)
      @language = fetch_language
      @database = fetch_database
      @model = model
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
    end

    def model
      if File.exists?(AMBER_YML) &&
         (yaml = YAML.parse(File.read AMBER_YML)) &&
         (model = yaml["model"]?)
        model.to_s
      else
        return "granite"
      end
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?(".#{@language}") }
    end
  end
end
