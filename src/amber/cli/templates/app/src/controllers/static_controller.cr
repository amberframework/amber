class StaticController < ApplicationController
  # If static resource is not found then raise an exception
  def index
    raise Amber::Exceptions::RouteNotFound.new(request)
  end
end
