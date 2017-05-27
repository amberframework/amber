require "teeplate"
require "./field.cr"

module Amber::CMD
  class Job < Teeplate::FileTree
    directory "#{__DIR__}/job"

    @name : String
    @fields : Array(Field)
    @database : String
    @db_url : String
    @wait_for : String

    def initialize(@name, fields)
      @database = database
      @db_url = ""
      @wait_for = ""
      @fields = fields.map {|field| Field.new(field)}
    end

    DATABASE_YML = "config/database.yml"
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



