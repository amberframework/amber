module Amber::Router::Session
  # All Session Stores should implement the following API
  abstract class AbstractStore
    abstract def id
    abstract def destroy
    abstract def [](key : String | Symbol)
    abstract def []?(key : String | Symbol)
    abstract def []=(key : String | Symbol, value)
    abstract def key?(key : String | Symbol)
    abstract def keys
    abstract def values
    abstract def to_h
    abstract def update(other_hash)
    abstract def delete(key : String | Symbol)
    abstract def fetch(key : String | Symbol, default = nil)
    abstract def empty?
  end
end
