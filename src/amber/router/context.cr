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
  setter flash : Amber::Router::Flash::FlashStore?
  setter cookies : Amber::Router::Cookies::Store?
  setter session : Amber::Router::Session::AbstractStore?
  property content : String?

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

  def session
    @session ||= Amber::Router::Session::Store.new(cookies).build
  end

  def flash
    @flash ||= Amber::Router::Flash.from_session_value(session.fetch(Amber::Pipe::Flash::PARAM_KEY, "{}"))
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
    @content = request_handler.call(self)
  end

  def valve
    request_handler.valve
  end

  def finalize_response
    response.print(@content)
  end
end
