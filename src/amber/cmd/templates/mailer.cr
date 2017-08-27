require "teeplate"
require "./field.cr"

module Amber::CMD
  class Mailer < Teeplate::FileTree
    directory "#{__DIR__}/mailer"

    @name : String
    @language : String
    @fields : Array(Field)

    def initialize(@name, fields)
      @language = language
      @fields = fields.map { |field| Field.new(field) }
    end

    def language
      if File.exists?(AMBER_YML) &&
         (yaml = YAML.parse(File.read AMBER_YML)) &&
         (language = yaml["language"]?)
        language.to_s
      else
        return "slang"
      end
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end
  end
end

