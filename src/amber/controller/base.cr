require "http"

require "./filters"
require "./helpers/*"

module Amber::Controller
  class Base
    include Helpers::CSRF
    include Helpers::Redirect
    include Helpers::Render
    include Helpers::Responders

    include Callbacks

    protected getter context : HTTP::Server::Context
    protected getter params : Amber::Validators::Params

    delegate :cookies, :format, :flash, :port, :requested_url, :session, :valve,
      :request_handler, :route, :websocket?, :get?, :post?, :patch?,
      :put?, :delete?, :head?, :client_ip, :request, :response, :halt!, to: context

    def initialize(@context : HTTP::Server::Context)
      @params = Amber::Validators::Params.new(context.params)
    end

    def controller_name
      self.class.name.gsub(/Controller/i, "")
    end
  end
end
