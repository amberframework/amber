module Amber::Controller
  module RedirectMethods
    def redirect_to(location : String, **args)
      Redirector.new(location, **args).redirect(self)
    end

    def redirect_to(action : Symbol, **args)
      Redirector.from_controller_action(controller_name, action, **args).redirect(self)
    end

    def redirect_to(controller : Symbol, action : Symbol, **args)
      Redirector.from_controller_action(controller.to_s, action, **args).redirect(self)
    end

    def redirect_back(**args)
      Redirector.new(request.headers["Referer"].to_s, **args).redirect(self)
    end
  end

  class Redirector
    DEFAULT_STATUS_CODE = 302
    LOCATION_HEADER     = "Location"

    getter location, status, params, flash

    @location : String
    @status : Int32 = DEFAULT_STATUS_CODE
    @params : Hash(String, String)? = nil
    @flash : Hash(String, String)? = nil

    def self.from_controller_action(controller : String, action : Symbol, **options)
      route = Amber::Server.router.match_by_controller_action(controller, action)
      raise Exceptions::Controller::Redirect.new("#{controller}##{action} not found!") unless route
      params = options[:params]?
      location, params = route.not_nil!.substitute_keys_in_path(params)
      status = options[:status]? || DEFAULT_STATUS_CODE
      new(location, status: status, params: params, flash: options[:flash]?)
    end

    def initialize(@location, @status = DEFAULT_STATUS_CODE, @params = nil, @flash = nil)
      raise_redirect_error(location) if location.empty?
    end

    def redirect(controller)
      set_flash(controller)
      url_path = encode_query_string(location, params)
      controller.response.headers.add LOCATION_HEADER, url_path
      controller.halt!(status, "Redirecting to #{url_path}")
    end

    private def encode_query_string(location, params)
      if !params.nil? && !params.empty?
        return location + "?" + HTTP::Params.encode(params).to_s
      end
      location
    end

    private def raise_redirect_error(location)
      if (!location.url? || !location.chars.first == '/')
        raise Exceptions::Controller::Redirect.new(location)
      end
    end

    private def set_flash(controller)
      controller.flash.merge!(flash.not_nil!) unless flash.nil?
    end
  end
end
