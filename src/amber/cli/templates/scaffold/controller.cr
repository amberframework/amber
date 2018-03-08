require "../field.cr"
require "inflector"

module Amber::CLI::Scaffold
  class Controller < Teeplate::FileTree
    include Amber::CLI::Helpers

    @name : String
    @fields : Array(Field)
    @visible_fields : Array(String)
    @database : String
    @language : String
    @fields_hash = {} of String => String

    def initialize(@name, fields)
      @language = CLI.config.language
      @database = CLI.config.database
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
      @visible_fields = visible_fields
      field_hash

      add_routes :web, <<-ROUTE
        resources "/#{Inflector.pluralize(@name)}", #{class_name}Controller
      ROUTE
    end

    def field_hash
      @fields.each do |f|
        if !%w(created_at updated_at).includes?(f.name)
          field_name = f.reference? ? "#{f.name}_id" : f.name
          @fields_hash[field_name] = default_value(f.cr_type) unless f.nil?
        end
      end
    end

    def visible_fields
      @fields.reject { |f| f.hidden }.map do |f|
        f.reference? ? "#{f.name}_id" : f.name
      end
    end

    private def default_value(field_type)
      case field_type.downcase
      when "int32", "int64", "integer"
        "1"
      when "float32", "float64", "float"
        "1.00"
      when "bool", "boolean"
        "true"
      when "time", "timestamp"
        Time.now.to_s
      when "ref", "reference", "references"
        rand(100).to_s
      else
        "Fake"
      end
    end
  end
end
