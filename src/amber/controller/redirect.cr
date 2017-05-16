module Amber::Controller
  # This class writes the redirect URL to the response headers and parses params.
  class LocationRedirect
    getter location, status, flash, query_params

    def initialize(@location : String,
                   @status = 302,
                   @query_params : Hash(String, String)? = nil)
      # Todo add flash as a parameter for redirect
      # Todo add default route scope for given controller action
      raise_redirect_error(location) if location.empty?
    end

    def redirect(for response)
      return set_location(response, location, status, query_params) if location.url?
      return set_location(response, location, status, query_params) if location.chars.first == '/'
      raise_redirect_error(location)
    end

    private def set_location(response, location, status = 302, query_params : _ = nil)
      url_path = encode_query_string(location, query_params)
      response.headers.add "Location", url_path
      response.status_code = status

      "Redirecting to #{url_path}"
    end

    def encode_query_string(location, query_params)
      return location + "?" + HTTP::Params.encode(query_params).to_s if query_params
      location
    end

    def raise_redirect_error(location)
      raise Exceptions::Controller::Redirect.new(location)
    end
  end

  module RedirectFactory
    def redirect_to(location : String, *args)
      LocationRedirect.new(location, *args).redirect(response)
    end

    # Redirects to the specified controller, action
    def redirect_to(controller : Symbol, action : Symbol, *args)
      LocationRedirect.new("/#{controller}/#{action}", *args).redirect(response)
    end

    # Redirects within the same controller
    def redirect_to(action : Symbol, *args)
      controller = self.class.to_s.chomp("Controller").downcase
      LocationRedirect.new("/#{controller}/#{action}", *args).redirect(response)
    end

    def redirect_back(*args)
      LocationRedirect.new(request.headers["Referer"]).redirect(response)
    end
  end
end
