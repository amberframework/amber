module Amber::Router
  struct Params
    property files = {} of String => File
    property store : HTTP::Params = HTTP::Params.new(Hash(String, Array(String)).new)

    forward_missing_to @store

    def json(key)
      JSON.parse(store[key]?.to_s)
    rescue JSON::ParseException
      raise "Value of params.json(#{key.inspect}) is not JSON!"
    end
  end
end
