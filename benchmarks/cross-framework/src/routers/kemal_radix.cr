require "radix"

# Adapter for the radix shard (used by Kemal).
# Uses a compressed radix tree (trie) for lookups.
#
# Note: radix does not support HTTP method dispatch -- it is purely
# a path-matching engine. This is fine for our comparison since we
# are benchmarking path matching performance specifically.
class KemalRadixRouter
  getter name : String = "radix (Kemal)"

  def initialize
    @tree = Radix::Tree(Symbol).new
  end

  def add_route(path : String, payload : Symbol) : Nil
    @tree.add(path, payload)
  end

  def lookup(path : String) : Bool
    @tree.find(path).found?
  end

  def supports_glob? : Bool
    true
  end
end
