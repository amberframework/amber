module Amber::Router
  class Params < Hash(String, String)
    alias KeyType = String | Symbol
    property files = {} of String => Amber::Router::Files::File

    def json(key : KeyType)
      JSON.parse(self[key]?.to_s)
    rescue JSON::ParseException
      raise "Value of params.json(#{key.inspect}) is not JSON!"
    end

    def []=(key : KeyType, value : V)
      super(key.to_s, value)
    end

    def find_entry(key : KeyType)
      super(key.to_s)
    end
  end
end
