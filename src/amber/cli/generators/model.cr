module Amber::CLI
  class Model < Generator
    command :model
    property migration : Generator
    property model : Generator

    def initialize(name, fields)
      super(name, fields)
      @migration = GraniteMigration.new(name, fields)
      @model = GraniteModel.new(name, fields)
    end

    def render(directory)
      migration.render(directory)
      model.render(directory)
    end
  end
end
