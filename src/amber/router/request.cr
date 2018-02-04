class HTTP::Request
  METHOD           = "_method"
  OVERRIDE_HEADER  = "X-HTTP-Method-Override"
  VALID_METHODS    =  %w(GET POST)
  @requested_method : String?
  @params : Amber::Router::Params?

  getter router : Amber::Router::Router = Amber::Server.router
  property matched_route : Radix::Result(Amber::Route)?

  def method
    return requested_method.to_s.upcase if override_method?
    @method
  end

  def requested_method
    @requested_method ||= params[METHOD]? || headers[OVERRIDE_HEADER]?
  end

  def override_method?
    VALID_METHODS.includes?(@method) && requested_method
  end

  def params
    @params ||= Amber::Router::Parse.params(self)
  end

  def port
    uri.port
  end

  def url
    uri.to_s
  end

  def route
    matched_route.payload
  end

  def route_params
    matched_route.params
  end

  def valid_route?
    matched_route.payload? || router.socket_route_defined?(self)
  end

  def process_websocket
    router.get_socket_handler(self)
  end

  private def matched_route
    @matched_route ||= router.match_by_request(self)
  end
end