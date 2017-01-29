require "teeplate"
require "./field.cr"
require "./entry.cr"

module Kemalyst::Generator
  class Model < Teeplate::FileTree
    directory "#{__DIR__}/model"

    @name : String
    @fields : Array(Field)
    @database: String
    @timestamp: String

    def initialize(@name, fields)
      @fields = fields.map {|field| Field.new(field)}
      @database = database
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
    end

    def database
      yaml_file = File.read("config/database.yml")
      yaml = YAML.parse(yaml_file)
      yaml.first.to_s
    end

  end
end

