require "teeplate"
require "./field.cr"
require "./entry.cr"

module Kemalyst::Generator
  class Migration < Teeplate::FileTree
    directory "#{__DIR__}/migration"

    @name : String
    @timestamp: String
    @fields : Array(Field)

    def initialize(@name, fields)
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
      @fields = fields.map {|field| Field.new(field)}
    end
  end
end

