require "http"
require "./store"

module Amber::Router::Cookies
  class PermanentStore < AbstractStore
    def get(name)
      @store.get(name)
    end

    def set(name : String, value : String, path : String = "/", expires : Time? = nil, domain : String? = nil, secure : Bool = false, http_only : Bool = false, extension : String? = nil)
      cookie = HTTP::Cookie.new(name, value, path, 20.years.from_now, domain, secure, http_only, extension)
      @store[name] = cookie
    end
  end
end
