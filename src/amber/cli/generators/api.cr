require "./generator"

module Amber::CLI
  class Api < Generator
    command :api
    property model : Generator
    property controller : Generator

    def initialize(name, fields)
      super(name, fields)
      @model = Model.new(name, fields)
      @controller = ApiController.new(name, fields)
    end

    def render(directory, **args)
      model.render(directory, **args)
      controller.render(directory, **args)
    end
  end
end
