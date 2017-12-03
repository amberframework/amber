module Amber::CLI
  class ErrorTemplate < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/error"

    @name : String
    @actions : Hash(String, String)
    @language : String = CLI.config.language

    def initialize(@name, actions)
      @actions = actions.map { |action| [action, "get"] }.to_h
      add_plugs
    end

    private def add_plugs
      add_plugs :web, "plug Amber::Pipe::Error.new"
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?(".#{@language}") }
    end
  end
end
