require "./base"

module Amber::Controller
  class Static < Base
    # If static resource is not found then raise an exception
    def index
      raise Amber::Exceptions::RouteNotFound.new(request)
    end
  end
end
