require "../../generators/field.cr"

module Amber::Recipes::Scaffold
  class View < Teeplate::FileTree
    include Amber::CLI::Helpers
    include FileEntries

    @name : String
    @fields : Array(Amber::CLI::Field)
    @visible_fields : Array(Amber::CLI::Field)
    @language : String = CLI.config.language
    @database : String = CLI.config.database
    @model : String = CLI.config.model

    @template : String | Nil
    @recipe : String

    def initialize(@name, @recipe, fields)
      @fields = fields.map { |field| Amber::CLI::Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Amber::CLI::Field.new(f, hidden: true, database: @database)
      end

      @visible_fields = @fields.reject { |f| f.hidden }

      @template = RecipeFetcher.new("scaffold", @recipe).fetch
      unless @template.nil?
        @template = (@template || "") + "/view"
      end
    end

    # setup the Liquid context
    def set_context(ctx)
      return if ctx.nil?

      ctx.set "name", @name
      ctx.set "class_name", class_name
      ctx.set "display_name", display_name
      ctx.set "fields", @fields
      ctx.set "visible_fields", @visible_fields
      ctx.set "language", @language
      ctx.set "database", @database
      ctx.set "model", @model
      ctx.set "recipe", @recipe
    end

    def isa_view?(entry_path)
      entry_path.includes?(".ecr") || entry_path.includes?(".slang")
    end

    def filter(entries)
      entries.reject { |entry| isa_view?(entry.path) && !entry.path.includes?(".#{@language}") }
    end
  end
end
