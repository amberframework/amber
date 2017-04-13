module Amber
    class Route
        getter :controller, :handler, :verb, :path, :params
        setter :params

        def initialize( verb : Symbol,
                        path : String,
                        controller : Controller,
                        handler : Proc(Nil),
                        params : Hash(String, String) | Nil = nil)
            @verb = verb
            @path = path
            @controller = controller
            @handler = handler
            @params = params
        end
    end
end
