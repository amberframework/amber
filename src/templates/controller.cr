require "teeplate"
require "./field.cr"

module Kemalyst::Generator
  class Controller < Teeplate::FileTree
    directory "#{__DIR__}/controller"

    @name : String
    @fields : Array(Field)

    def initialize(@name, fields)
      @fields = fields.map {|field| Field.new(field)}
    end
  end
end


