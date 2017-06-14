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
    protected getter flash : Amber::Router::Flash::Params
    protected getter session : Amber::Router::Session::Params
    protected getter cookies : Amber::Router::Cookies::Store?

    def initialize(@context : HTTP::Server::Context)
      @request = context.request
      @response = context.response
      @raw_params = context.params
      @flash = context.flash
      @session = context.session
      @params = Amber::Validators::Params.new(@raw_params)
    end

    def cookies
      @cookies ||= context.cookies
    end
  end
end
