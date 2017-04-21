require "http"
require "./validator"

module Amber
  module Controller
    class Base
      property request : HTTP::Request?
      property response : HTTP::Server::Response?
      property raw_params : HTTP::Params = HTTP::Params.parse("t=t")
      property context : HTTP::Server::Context?
      property params = Params::Validator.new(raw_params)

      protected def set_context(@context : HTTP::Server::Context)
        self.request = context.request
        self.response = context.response
        self.raw_params = context.params
        self.params = Params::Validator.new(raw_params)
      end
    end
  end
end
