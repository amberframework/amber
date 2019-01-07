require "http"
require "./store"

module Amber::Router::Cookies
  class PermanentStore
    getter store : Store

    def initialize(@store)
    end

    def [](name)
      get(name)
    end

    def get(name)
      @store.get(name)
    end

    def []=(name, value)
      set(name, value)
    end

    def set(name : String, value : String, path : String = "/", domain : String? = nil, secure : Bool = false, http_only : Bool = false, extension : String? = nil)
      cookie = HTTP::Cookie.new(name, value, path, 20.years.from_now, domain, secure, http_only, extension)
      @store[name] = cookie
    end
  end
end
