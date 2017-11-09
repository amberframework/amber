module Amber::Router
  # The Parameters module will parse parameters from a URL, a form post or a JSON
  # post and provide them in the self params hash.  This unifies access to
  # parameters into one place to simplify access to them.
  # Note: other params from the router will be handled in the router handler
  # instead of here.  This removes a dependency on the router in case it is
  # replaced or not needed.

  class Params < Hash(String, String)
    alias KeyType = String | Symbol

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
