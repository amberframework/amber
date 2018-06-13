require "./field.cr"
require "../helpers/migration"

module Amber::CLI
  class Migration < Teeplate::FileTree
    include Helpers
    include Helpers::Migration
    directory "#{__DIR__}/migration/empty"

    @name : String
    @fields : Array(Field)
    @database : String = CLI.config.database
    @timestamp : String
    @primary_key : String

    def initialize(@name, fields)
      @timestamp = current_timestamp
      @fields = fields.map { |field| Field.new(field, database: @database) } + extra_fields
      @primary_key = primary_key
    end

    private def extra_fields
      %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
    end
  end
end
