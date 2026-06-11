require "../../../../src/amber/router/engine"

# Adapter for the Amber V2 internalized routing engine.
# Uses hash-indexed fixed segments for O(1) lookups.
class AmberV2Router
  getter name : String = "Amber V2"

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
