require "./generator"

module Amber::CLI
  class Api < Generator
    property migration : Generator
    property model : Generator
    property controller : Generator

    def initialize(name, fields)
      super(name, fields)
      if config.model == "crecto"
        @migration = CrectoMigration.new(name, fields)
        @model = CrectoModel.new(name, fields)
        @controller = ApiCrectoController.new(name, fields)
      else
        @migration = GraniteMigration.new(name, fields)
        @model = GraniteModel.new(name, fields)
        @controller = ApiGraniteController.new(name, fields)
      end
    end

    def render(directory)
      migration.render(directory)
      model.render(directory)
      controller.render(directory)
    end
  end
end
