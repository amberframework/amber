require "http"

require "./filters"
require "./params_validator"
require "./helpers/*"

module Amber::Controller
  class Base
    include Helpers::CSRF
    include Helpers::Redirect
    include Helpers::Render
    include Helpers::Responders
    include Helpers::Route
    include Helpers::I18n
    include Callbacks

    protected getter context : HTTP::Server::Context
    protected getter raw_params : Amber::Router::Params

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
      :response,
      :route,
      :session,
      :valve,
      :websocket?,
      to: context

    def initialize(@context : HTTP::Server::Context)
      @raw_params = context.params
    end

    macro params(klass, key = "")
      class {{klass.id}}
        include ParamsValidator

        def self.instance(raw_params)
          @@instance ||= new(raw_params, {{key.stringify.id}})
        end

        getter errors = [] of Error
        @raw_params : Amber::Router::Params

        {{yield}}
      end

      getter {{klass.id.downcase}} = {{klass.id}}.instance(@raw_params)
    end
  end
end
