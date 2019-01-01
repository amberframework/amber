module Amber::CLI
  class Scaffold < Generator
    property migration : Generator
    property model : Generator
    property controller : Generator
    property view : Generator

    def initialize(name, fields)
      super(name, fields)
      if config.model == "crecto"
        @migration = CrectoMigration.new(name, fields)
        @model = CrectoModel.new(name, fields)
        @controller = ScaffoldCrectoController.new(name, fields)
      else
        @migration = GraniteMigration.new(name, fields)
        @model = GraniteModel.new(name, fields)
        @controller = ScaffoldGraniteController.new(name, fields)
      end
      @view = ScaffoldView.new(name, fields)
    end

    def render(directory)
      migration.render(directory)
      model.render(directory)
      controller.render(directory)
      view.render(directory)
    end
  end
end
