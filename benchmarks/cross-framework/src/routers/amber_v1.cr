require "amber_router"

# Adapter for the amber_router v0.4.4 shard (used by Amber V1).
# Uses a segment tree with linear scan for lookups.
class AmberV1Router
  getter name : String = "Amber V1 (amber_router)"

  def initialize
    @router = Amber::Router::RouteSet(Symbol).new
  end

  def add_route(path : String, payload : Symbol) : Nil
    @router.add(path, payload)
  end

  def lookup(path : String) : Bool
    @router.find(path).found?
  end

  def supports_glob? : Bool
    true
  end
end
