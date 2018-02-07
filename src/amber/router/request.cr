require "./params"

class HTTP::Request
  include Amber::Router::Parse
  METHOD           = "_method"
  OVERRIDE_HEADER  = "X-HTTP-Method-Override"

  @route : Amber::Route?
  @radix_route : Radix::Tree(Amber::Route)?
  @requested_method : String?
  @params : Amber::Router::Params = Amber::Router::Params.new

  def method
    case @method
    when "GET", "POST" then requested_method.to_s.upcase
    else @method
    end
  end

  def requested_method
    @requested_method ||= params[METHOD]? || headers[OVERRIDE_HEADER]? || @method
  end

  def port
    uri.port
  end

  def url
    uri.to_s
  end

  def route
    @route ||= matched_route.payload
  end

  def valid_route?
    matched_route.payload? || router.socket_route_defined?(self)
  end

  def process_websocket
    router.get_socket_handler(self)
  end

  def matched_route
    radix_route = router.match_by_request(self)
    radix_route.params.each { |k,v| @params.store.add(k, v) }
    radix_route
  end

  private def router
    Amber::Server.router
  end
end
