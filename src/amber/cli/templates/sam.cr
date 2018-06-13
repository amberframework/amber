require "./field.cr"

module Amber::CLI
  class Sam < Teeplate::FileTree
    include Amber::CLI::Helpers

    directory "#{__DIR__}/sam"

    @model : String

    def initialize(@model)
    end
  end
end
