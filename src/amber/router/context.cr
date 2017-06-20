require "./**"

# The Context holds the request and the response objects.  The context is
# passed to each handler that will read from the request object and build a
# response object.  Params and Session hash can be accessed from the Context.
class HTTP::Server::Context
  include Amber::Router::Files
  include Amber::Router::Session
  include Amber::Router::Flash
  include Amber::Router::Params

  property route : Radix::Result(Amber::Route)
  getter router : Amber::Router::Router

  @cookies : Amber::Router::Cookies::Store?

  def initialize(@request : HTTP::Request, @response : HTTP::Server::Response)
    @router = Amber::Router::Router.instance
    parse_params
    override_request_method!
    @route = router.match_by_request(@request)
    merge_route_params
  end

  def cookies
    @cookies ||= Amber::Router::Cookies::Store.build(
      request, Amber::Server.key_generator
    )
  end

  def invalid_route?
    !route.payload? && !router.socket_route_defined?(@request)
  end

  def websocket?
    request.headers["Upgrade"]? == "websocket"
  end

  def request_handler
    route.payload
  end

  def process_websocket_request
    router.get_socket_handler(request).call(self)
  end

  def process_request
    request_handler.call(self)
  end

  def valve
    request_handler.valve
  end
end
