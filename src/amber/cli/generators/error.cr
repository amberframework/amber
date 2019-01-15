module Amber::CLI
  class ErrorTemplate < Generator
    command :error
    directory "#{__DIR__}/../templates/error"
    getter actions : Array(String)

    def initialize(name, fields)
      super(name, nil)

      @actions = ["forbidden", "not_found", "internal_server_error"]
    end

    def pre_render(directory)
      add_plugs
    end

    private def add_plugs
      add_plugs :web, "plug Amber::Pipe::Error.new"
    end
  end
end
