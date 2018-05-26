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
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S%L")
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
      @primary_key = primary_key
    end
  end
end
