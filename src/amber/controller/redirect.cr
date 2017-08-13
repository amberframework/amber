module Amber::Controller
  # This class writes the redirect URL to the response headers and parses params.
  class LocationRedirect
    getter location, status, params, flash

    @location : String
    @status : Int32 = 302
    @params : Hash(String, String)? = nil
    @flash : Hash(String, String)? = nil

    def initialize(@location, @status = 302, @params = nil, @flash = nil)
      raise_redirect_error(location) if location.empty?
    end

    def redirect(for context)
      response = context.response
      context.flash.merge!(flash.not_nil!) if !flash.nil?
      raise_redirect_error(location) unless location.url? || location.chars.first == '/'
      set_location(response, location, status, params)
    end

    private def set_location(response, location, status = 302, params : _ = nil)
      url_path = encode_query_string(location, params)
      response.headers.add "Location", url_path
      response.status_code = status
    end

    def encode_query_string(location, params)
      return location + "?" + HTTP::Params.encode(params).to_s if params
      location
    end

    def raise_redirect_error(location)
      raise Exceptions::Controller::Redirect.new(location)
    end
  end

  module RedirectFactory
    def redirect_to(location : String, **args)
      LocationRedirect.new(location, **args).redirect(context)
      halt!(response.status_code, "Redirecting to #{response.headers["Location"]}")
    end

    # Redirects to the specified controller, action
    def redirect_to(controller : Symbol, action : Symbol, **args)
      LocationRedirect.new("/#{controller}/#{action}", **args).redirect(context)
      halt!(response.status_code, "Redirecting to #{response.headers["Location"]}")
    end

    # Redirects within the same controller
    def redirect_to(action : Symbol, **args)
      LocationRedirect.new("/#{controller_name}/#{action}", **args).redirect(context)
      halt!(response.status_code, "Redirecting to #{response.headers["Location"]}")
    end

    def redirect_back(**args)
      LocationRedirect.new(request.headers["Referer"], status: 302).redirect(context)
      halt!(response.status_code, "Redirecting to #{response.headers["Location"]}")
    end
  end
end
