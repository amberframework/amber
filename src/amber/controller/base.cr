require "http"

module Amber::Controller
  class Base
    include Amber::Support::DSL::ControllerActions

    property request : HTTP::Request?
    property response : HTTP::Server::Response?
    property raw_params : HTTP::Params?
    property context : HTTP::Server::Context?

    protected def set_context(@context : HTTP::Server::Context)
      self.request = context.request
      self.response = context.response
      self.raw_params = context.params
    end
  end
end
