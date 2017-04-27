module Amber::Controller
  module Redirect
    # Supports redirection in the following signatures
    #
    # reditect_to location, status
    # redirect_to "/new"
    # redirect_to "/home/index"
    # redirect_to :back
    # redirect_to :show
    # redirect_to "http://www.ambercr.io"
    def redirect_to(location : String | Symbol, status = 302)
      response.headers.add "Location", parse_redirect(location)
      response.status_code = status
    end

    private def parse_redirect(location)
      return string_location(location) if location.is_a? String
      return back() if location == :back
      return "/#{location}" if location.is_a? Symbol
      location
    end

    private def string_location(location)
      return location if location.url?
      return location if location.chars[0] != "/"
      raise_error(location)
    end

    private def back
      referer = request.headers["Referer"]?
      return referer if !referer.nil? && !referer.empty?
      raise Exceptions::Controller::Redirect.new(:back)
    end

    private def raise_error(location)
      raise Exceptions::Controller::Redirect.new(location)
    end
  end
end
