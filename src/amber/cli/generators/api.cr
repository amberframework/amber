require "./generator"

module Amber::CLI
  class Api < Generator
    command :api
    property migration : Generator
    property model : Generator
    property controller : Generator

    def initialize(name, fields)
      super(name, fields)
      case config.model
      when "clear"
        @migration = ClearMigration.new(name, fields)
        @model = ClearModel.new(name, fields)
        @controller = ApiClearController.new(name, fields)
      when "crecto"
        @migration = CrectoMigration.new(name, fields)
        @model = CrectoModel.new(name, fields)
        @controller = ApiCrectoController.new(name, fields)
      else # "granite"
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
