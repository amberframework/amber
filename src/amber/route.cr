module Amber
  class Route
    property :controller, :handler, :verb, :resource, :params
    getter controller : Amber::Controller

    def initialize(verb : String | Symbol,
                   resource : String,
                   controller = Controller.new,
                   handler : Proc(String) = ->{ "500" },
                   params : Hash(String, String) | Nil = nil)
      @verb = verb
      @resource = resource
      @controller = controller
      @handler = handler
      @params = params
    end
  end
end
