require "http"
require "./**"

module Amber::Controller
  class Base
    include Render
    include RedirectMethods
    include Callbacks
    include Helpers::Tag

    protected getter raw_params : HTTP::Params
    protected getter context : HTTP::Server::Context
    protected getter params : Amber::Validators::Params

    delegate :cookies, :format, :flash, :port, :requested_url, :session, :invalid_route, :valve,
      :request_handler, :route, :websocket?, :invalid_route?, :get?, :post?, :patch?,
      :put?, :delete?, :head?, :client_ip, :request, :response, to: context

    def initialize(@context : HTTP::Server::Context)
      @raw_params = context.params
      @params = Amber::Validators::Params.new(@raw_params)
    end

    # TODO: Move this method to Context
    #
    # Now that we are delegating to context we should be
    # able to move this method to the HTTP::Server context class
    # Not doing it now because of some refactoring that needs to happen
    # and is a little out of scope for this PR since it touches a lot of
    # moving pieces
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
