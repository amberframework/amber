module Amber::CLI
  class Scaffold < Generator
    command :scaffold
    property migration : Generator
    property model : Generator
    property controller : Generator
    property view : Generator

    def initialize(name, fields)
      super(name, fields)
      @migration = GraniteMigration.new(name, fields)
      @model = GraniteModel.new(name, fields)
      @controller = ScaffoldGraniteController.new(name, fields)
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
