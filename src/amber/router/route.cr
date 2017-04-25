module Amber
  class Route
    property :controller, :handler, :verb, :resource, :valve, :params
    getter controller : Controller::Base

    def initialize(verb : String | Symbol,
                   resource : String,
                   controller = Controller::Base.new,
                   handler : Proc(String) = ->{ "500" },
                   valve : Symbol = :web)
      @verb = verb
      @resource = resource
      @controller = controller
      @handler = handler
      @valve = valve
    end
  end
end
