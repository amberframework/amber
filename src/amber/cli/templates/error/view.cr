require "../field.cr"

module Amber::CLI::ErrorTemplate
  class View < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/view"

    @name : String
    @actions : Array(String)
    @language : String

    def initialize(@name, @actions)
      @language = fetch_language
    end

  end
end
