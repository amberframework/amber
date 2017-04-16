require "teeplate"
require "./field.cr"

module Kemalyst::Generator
  class Controller < Teeplate::FileTree
    directory "#{__DIR__}/controller"

    @name : String
    @fields : Array(Field)
    @language : String

    def initialize(@name, fields)
      @language = language
      @fields = fields.map {|field| Field.new(field)}
    end

    def language
      return "slang" unless File.exists? ".kgen.yml"
      yaml_file = File.read(".kgen.yml")
      yaml = YAML.parse(yaml_file)
      yaml["language"].to_s
    end
  end
end


