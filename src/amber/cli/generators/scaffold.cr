module Amber::CLI
  class Scaffold < Generator
    command :scaffold
    property model : Generator
    property controller : Generator
    property view : Generator

    def initialize(name, fields)
      super(name, fields)
      @model = Model.new(name, fields)
      @view = ScaffoldView.new(name, fields)
      @controller = ScaffoldController.new(name, fields)
    end

    def render(directory, **args)
      model.render(directory, **args)
      view.render(directory, **args)
      controller.render(directory, **args)
    end
  end
end
