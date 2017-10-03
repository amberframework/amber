require "./field.cr"

module Amber::CLI
  class CrectoController < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/controller/crecto"

    @name : String
    @fields : Array(Field)
    @visible_fields : Array(String)
    @language : String

    def initialize(@name, actions)
      @language = language
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

    def add_views
      @actions.each do |action, verb|
        `mkdir -p src/views/#{@name}`
        `touch src/views/#{@name}/#{action}.#{language}`
      end
    end
  end
end
