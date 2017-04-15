require "teeplate"
require "./field.cr"

module Kemalyst::Generator
  class Scaffold < Teeplate::FileTree
    directory "#{__DIR__}/scaffold"

    @name : String
    @fields : Array(Field)
    @database : String
    @language : String
    @timestamp : String
    @primary_key : String

    def initialize(@name, fields)
      @database = database
      @language = language
      @fields = fields.map {|field| Field.new(field, database: @database)}
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
      @primary_key = primary_key
    end

    def database
      yaml_file = File.read("config/database.yml")
      yaml = YAML.parse(yaml_file)
      yaml.first.to_s
    end

    def language
      return "slang" unless File.exists? ".kgen.yml"
      yaml_file = File.read(".kgen.yml")
      yaml = YAML.parse(yaml_file)
      yaml["language"].to_s
    end

    def primary_key
      case @database
      when "pg"
        "id BIGSERIAL PRIMARY KEY"
      when "mysql"
        "id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY"
      else
        "id INTEGER NOT NULL PRIMARY KEY"
      end
    end

    def filter(entry)
      return entry.path.includes?("src/views") && !entry.path.includes?("#{@language}")
    end
  end
end
