require "./params"
require "./router"
require "./route"

class HTTP::Request
  METHOD          = "_method"
  OVERRIDE_HEADER = "X-HTTP-Method-Override"

  @matched_route : Amber::Router::RoutedResult(Amber::Route)?
  @requested_method : String?
  @params : Amber::Router::Params?

  def method
    case @method
    when "POST" then requested_method.to_s.upcase
    else             @method
    end
  end

  def requested_method
    @requested_method ||= params.override_method?(METHOD) || headers[OVERRIDE_HEADER]? || @method
  end

  def params
    @params ||= Amber::Router::Params.new(self)
  end

  def port
    uri.port
  end

  def url
    uri.to_s
  end

  def route
    matched_route.payload.not_nil!
  end

  def valid_route?
    matched_route.payload? || router.socket_route_defined?(self)
  end

  def process_websocket
    router.get_socket_handler(self)
  end

  def matched_route
    @matched_route ||= router.match_by_request(self)
  end

  private def router
    Amber::Server.router
  end
end
