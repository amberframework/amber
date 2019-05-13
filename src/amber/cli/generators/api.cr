require "./generator"

module Amber::CLI
  class Api < Generator
    command :api
    property migration : Generator
    property model : Generator
    property controller : Generator

    def initialize(name, fields)
      super(name, fields)
      @migration = GraniteMigration.new(name, fields)
      @model = GraniteModel.new(name, fields)
      @controller = ApiGraniteController.new(name, fields)
    end

    def render(directory)
      migration.render(directory)
      model.render(directory)
      controller.render(directory)
    end
  end
end
