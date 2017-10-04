require "./field.cr"

module Amber::CLI
  class Migration < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/migration/empty"

    @name : String
    @fields : Array(Field)
    @database : String
    @timestamp : String
    @primary_key : String

    def initialize(@name, fields)
      @fields = fields.map { |field| Field.new(field) }
      @database = database
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
      @primary_key = primary_key
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
