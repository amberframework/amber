require "./field.cr"

module Amber::CLI
  class View < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/view"

    @name : String
    @language : String
    @fields : Array(Field)

    def initialize(@name, fields)
      @language = CLI.config.language
      @fields = fields.map { |field| Field.new(field) }

      add_dependencies <<-DEPENDENCY
      require "../src/views/**"
      DEPENDENCY
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end
  end
end
