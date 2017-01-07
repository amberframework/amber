require "teeplate"

module Kemalyst::Generator
  class Scaffold < Teeplate::FileTree
    directory "#{__DIR__}/scaffold"

    @name : String
    @fields : Array(String)

    def initialize(@name, @fields)
    end
  end
end
