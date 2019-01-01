require "./model"

module Amber::CLI
  class GraniteModel < Generator
    directory "#{__DIR__}/../templates/model/granite"

    def initialize(name, fields)
      super(name, fields)
      add_timestamp_fields
    end

    def pre_render(directory)
      add_dependencies
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      DEPENDENCY
    end
  end
end
