require "./field.cr"

module Amber::CLI
  class Model < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/model/granite"

    @name : String
    @fields : Array(Field)
    @database : String

    def initialize(@name, fields)
      @database = database
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end

      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      DEPENDENCY
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
  end
end
