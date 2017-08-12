require "http"
require "./**"

module Amber::Controller
  class Base
    include Render
    include RedirectFactory
    include Callbacks
    include Helpers::Tag

    protected getter request : HTTP::Request
    protected getter response : HTTP::Server::Response
    protected getter raw_params : HTTP::Params
    protected getter context : HTTP::Server::Context
    protected getter params : Amber::Validators::Params

    def initialize(@context : HTTP::Server::Context)
      @request = context.request
      @response = context.response
      @raw_params = context.params
      @params = Amber::Validators::Params.new(@raw_params)
    end

    def cookies
      context.cookies
    end

    def flash
      context.flash
    end

    def session
      context.session
    end

    def halt!(status_code : Int32 = 200, content = "")
      response.headers["Content-Type"] = "text/plain"
      response.status_code = status_code
      context.content = content
    end

    def controller_name
      self.class.name.downcase.gsub("controller", "")
    end
  end
end
