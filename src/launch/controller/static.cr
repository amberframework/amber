require "./base"

module Launch::Controller
  class Static < Base
    # If static resource is not found then raise an exception
    def index
      raise Launch::Exceptions::RouteNotFound.new(request)
    end
  end
end
