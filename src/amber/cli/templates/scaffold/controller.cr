require "../field.cr"

module Amber::CLI::Scaffold
  class Controller < Teeplate::FileTree
    include Amber::CLI::Helpers

    @name : String
    @fields : Array(Field)
    @visible_fields : Array(String)
    @database : String
    @language : String

    def initialize(@name, fields)
      @language = language
      @database = database
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
      @visible_fields = visible_fields

      add_routes :web, <<-ROUTE
        resources "/#{@name}s", #{@name.capitalize}Controller
      ROUTE
    end

    def language
      if File.exists?(AMBER_YML) &&
         (yaml = YAML.parse(File.read AMBER_YML)) &&
         (language = yaml["language"]?)
        language.to_s
      else
        return "slang"
      end
    end

    def database
      if File.exists?(AMBER_YML) &&
         (yaml = YAML.parse(File.read AMBER_YML)) &&
         (database = yaml["database"]?)
        database.to_s
      else
        return "pg"
      end
    end

    def visible_fields
      @fields.reject { |f| f.hidden }.map do |f|
        f.reference? ? "#{f.name}_id" : f.name
      end
    end
  end
end
