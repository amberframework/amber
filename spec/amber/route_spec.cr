require "./../spec_helper"

module Amber
  describe Route do
    it "Initializes correctly with Decendant controller" do
      controller = HelloController.new
      world = ->controller.world

      route = Route.new("GET", "/", controller, world)

      route.class.should eq Route
    end
  end
end
