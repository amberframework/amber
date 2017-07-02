require "teeplate"
# require "./field.cr"

module Amber::CMD
  class Spec < Teeplate::FileTree
    directory "#{__DIR__}/spec"

    @name : String

    def initialize(@name)

    end

  end
end
