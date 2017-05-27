require "teeplate"
require "./field.cr"

module Amber::CMD
  class Model < Teeplate::FileTree
    directory "#{__DIR__}/model"

    @name : String
    @fields : Array(Field)
    @database: String
    @timestamp: String
    @primary_key : String

    def initialize(@name, fields)
      @database = database
      @fields = fields.map {|field| Field.new(field, database: @database)}
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
      @primary_key = primary_key
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

    def primary_key
      case @database
      when "pg"
        "id BIGSERIAL PRIMARY KEY"
      when "mysql"
        "id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY"
      when "sqlite"
        "id INTEGER NOT NULL PRIMARY KEY"
      else
        "id INTEGER NOT NULL PRIMARY KEY"
      end
    end
  end
end

