require "../templates/field.cr"

module Amber::Recipes
  class Model < Teeplate::FileTree
    include Amber::CLI::Helpers
    include FileEntries

    @name : String
    @fields : Array(Amber::CLI::Field)
    @model : String = CLI.config.model
    @database : String = CLI.config.database

    @recipe : String?
    @template : String?
    @table_name : String?

    def initialize(@name, @recipe, fields)
      @fields = fields.map { |field| Amber::CLI::Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Amber::CLI::Field.new(f, hidden: true, database: @database)
      end

      @template = RecipeFetcher.new("model", @recipe).fetch

      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      DEPENDENCY
    end

    # setup the Liquid context
    def set_context(ctx)
      return if ctx.nil?

      ctx.set "class_name", class_name
      ctx.set "display_name", display_name
      ctx.set "name", @name
      ctx.set "fields", @fields
      ctx.set "database", @database
      ctx.set "table_name", table_name
      ctx.set "model", @model
      ctx.set "recipe", @recipe
    end

    def table_name
      @table_name ||= name_plural
    end
  end
end
