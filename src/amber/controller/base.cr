require "http"

require "./filters"
require "./helpers/csrf"
require "./helpers/redirect"
require "./helpers/responders"
require "./helpers/route"

module Amber::Controller
  class Base
    include Helpers::CSRF
    include Helpers::Redirect
    include Helpers::Responders
    include Helpers::Route
    include Callbacks

    protected getter context : HTTP::Server::Context
    protected getter params : Amber::Validators::Params

    delegate :logger, to: Amber.settings

    delegate :client_ip,
      :cookies,
      :delete?,
      :flash,
      :format,
      :get?,
      :halt!,
      :head?,
      :patch?,
      :port,
      :post?,
      :put?,
      :request,
      :requested_url,
      :request_handler,
      :response,
      :route,
      :session,
      :valve,
      :websocket?,
    to: context

    def initialize(@context : HTTP::Server::Context)
      @params = Amber::Validators::Params.new(context.params)
    end
  end
end
