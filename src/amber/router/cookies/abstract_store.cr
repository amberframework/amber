module Amber::Router::Cookies
  abstract class AbstractStore
    getter store : Store

    def initialize(@store)
    end

    def [](name)
      get(name)
    end

    def []=(name, value)
      set(name, value)
    end

    abstract def get(name)

    abstract def set(name : String, value : String, path : String = "/", expires : Time? = nil, domain : String? = nil, secure : Bool = false, http_only : Bool = false, extension : String? = nil)
  end
end
