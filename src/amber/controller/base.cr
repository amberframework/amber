require "http"
require "./*"

module Amber::Controller
  class Base
    include Render
    include Redirect
    include FilterHelper

    protected getter request = HTTP::Request.new("GET", "/")
    protected getter response = HTTP::Server::Response.new(IO::Memory.new)
    protected getter raw_params = HTTP::Params.parse("")
    protected getter context : HTTP::Server::Context?
    protected getter params : Amber::Validators::Params?

    def set_context(@context : HTTP::Server::Context)
      @request = context.request
      @response = context.response
      @raw_params = context.params
      @params = Amber::Validators::Params.new(@raw_params)
    end
  end
end
