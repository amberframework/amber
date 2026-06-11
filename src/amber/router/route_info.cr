module Amber::Router
  struct RouteInfo
    include JSON::Serializable

    getter verb : String
    getter path : String
    getter controller : String
    getter action : String
    getter valve : String
    getter scope : String
    getter name : String?
    getter constraints : Hash(String, String)

    def initialize(@verb, @path, @controller, @action, @valve, @scope,
                   @name = nil, @constraints = {} of String => String)
    end

    def to_s(io : IO)
      io << verb.ljust(8)
      io << path.ljust(40)
      io << "#{controller}##{action}".ljust(40)
      io << valve.ljust(10)
      io << (name || "").ljust(20)
    end
  end
end
