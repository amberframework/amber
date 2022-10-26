require "../../generators/field.cr"

module Amber::Recipes::Scaffold
  class Controller < Teeplate::FileTree
    include Amber::CLI::Helpers
    include FileEntries

    @name : String
    @fields : Array(Amber::CLI::Field)
    @visible_fields : Array(Amber::CLI::Field)
    @database : String
    @language : String
    @model : String
    @fields_hash = {} of String => String

    @template : String | Nil
    @recipe : String

    def initialize(@name, @recipe, fields)
      @language = CLI.config.language
      @database = CLI.config.database
      @model = CLI.config.model
      @fields = fields.map { |field| Amber::CLI::Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Amber::CLI::Field.new(f, hidden: true, database: @database)
      end
      @visible_fields = @fields.reject(&.hidden)
      field_hash

      @template = RecipeFetcher.new("scaffold", @recipe).fetch
      if !@template.nil?
        @template = (@template || "") + "/controller"
      end

      add_routes :web, <<-ROUTE
        resources "#{name_plural}", #{class_name}Controller
      ROUTE
    end

    # setup the Liquid context
    def set_context(ctx)
      return if ctx.nil?

      ctx.set "class_name", class_name
      ctx.set "display_name", display_name
      ctx.set "name", @name
      ctx.set "fields", @fields
      ctx.set "fields_hash", @fields_hash.to_s
      ctx.set "visible_fields", @visible_fields
      ctx.set "language", @language
      ctx.set "database", @database
      ctx.set "model", @model
      ctx.set "recipe", @recipe
    end

    def field_hash
      @fields.each do |f|
        if !%w(created_at updated_at).includes?(f.name)
          field_name = f.reference? ? "#{f.name}_id" : f.name
          @fields_hash[field_name] = default_value(f.cr_type) unless f.nil?
        end
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
        Time.utc.to_s
      when "ref", "reference", "references"
        rand(100).to_s
      else
        "Fake"
      end
    end
  end
end
