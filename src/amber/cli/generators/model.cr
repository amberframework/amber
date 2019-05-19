require "./model"

module Amber::CLI
  class Model < Generator
    command :model
    directory "#{__DIR__}/../templates/model"

    property migration : Generator

    def initialize(name, fields)
      super(name, fields)
      @migration = Amber::CLI::Migration.new(name, fields)
      add_timestamp_fields
    end

    def pre_render(directory, **args)
      add_dependencies
    end

    def render(directory, **args)
      super(directory, **args)
      migration.render(directory, **args)
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      DEPENDENCY
    end
  end
end
