require "teeplate"
require "./field.cr"

module Kemalyst::Generator
  class Mailer < Teeplate::FileTree
    directory "#{__DIR__}/mailer"

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

    def filter(entries)
      entries.reject{|entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end
  end
end
