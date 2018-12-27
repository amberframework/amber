module Amber::CLI
  class ErrorTemplate < Generator
    directory "#{__DIR__}/../templates/error"
    getter actions : Array(String)

    def initialize(name, fields)
      super(name, nil)

      @actions = ["forbidden", "not_found", "internal_server_error"]
    end

    def pre_render(directory)
      add_plugs
      add_dependencies
    end

    private def add_plugs
      add_plugs :web, "plug Amber::Pipe::Error.new"
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/pipes/error.cr"
      DEPENDENCY
    end
  end
end
