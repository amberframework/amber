require "teeplate"

module Kemalyst::Generator
  class Resource < Teeplate::FileTree
    directory "#{__DIR__}/resource"

    @name : String

    def initialize(@name)
    end
  end
end
