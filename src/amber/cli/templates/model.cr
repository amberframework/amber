require "./field.cr"

module Amber::CLI
  class Model < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/model/granite"

    @name : String
    @fields : Array(Field)
    @database : String = CLI.config.database

    def initialize(@name, fields)
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end

      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      DEPENDENCY
    end

    def table_name
      @table_name ||= "#{@name}s"
    end
  end
end
