require "teeplate"
require "./field.cr"

module Kemalyst::Generator
  class Job < Teeplate::FileTree
    directory "#{__DIR__}/job"

    @name : String
    @fields : Array(Field)

    def initialize(@name, fields)
      @fields = fields.map {|field| Field.new(field)}
    end
  end
end



