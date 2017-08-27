require "teeplate"
require "./field.cr"

module Amber::CMD
  class Migration < Teeplate::FileTree
    directory "#{__DIR__}/migration"

    @name : String
    @fields : Array(Field)
    @database : String
    @timestamp : String

    def initialize(@name, fields)
      @fields = fields.map { |field| Field.new(field) }
      @database = database
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
    end

    def database
      if File.exists?(DATABASE_YML) &&
         (yaml = YAML.parse(File.read DATABASE_YML)) &&
         (database = yaml.first)
        database.to_s
      else
        return "pg"
      end
    end
  end
end
