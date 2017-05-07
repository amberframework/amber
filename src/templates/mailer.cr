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

    KGEN_YML = ".kgen.yml"
    def language
      if File.exists?(KGEN_YML) &&
        (yaml = YAML.parse(File.read KGEN_YML)) &&
        (language = yaml["language"]?)
        language.to_s
      else
        return "slang"
      end
    end

    def filter(entries)
      entries.reject{|entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end
  end
end
