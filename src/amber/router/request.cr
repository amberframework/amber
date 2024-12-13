require "./params"
require "./router"
require "./route"

class HTTP::Request
  METHOD = "_method"
  
  @matched_route : Amber::Router::RoutedResult(Amber::Route)?
  @requested_method : String?
  @params : Amber::Router::Params?

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
