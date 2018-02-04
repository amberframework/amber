require "./**"

class HTTP::Request
  def port
    uri.port
  end

  def url
    uri.to_s
  end
end

# The Context holds the request and the response objects.  The context is
# passed to each handler that will read from the request object and build a
# response object.  Params and Session hash can be accessed from the Context.
class HTTP::Server::Context
  METHODS = %i(get post put patch delete head)

  include Amber::Router::Files
  include Amber::Router::Session
  include Amber::Router::Flash
  include Amber::Router::ParamsParser

  getter router : Amber::Router::Router
  setter flash : Amber::Router::Flash::FlashStore?
  setter cookies : Amber::Router::Cookies::Store?
  setter session : Amber::Router::Session::AbstractStore?
  property content : String?
  property route : Radix::Result(Amber::Route)

  def initialize(@request : HTTP::Request, @response : HTTP::Server::Response)
    @router = Amber::Server.router
    parse_params
    override_request_method!
    @route = router.match_by_request(@request)
    merge_route_params
  end

  def cookies
    @cookies ||= Amber::Router::Cookies::Store.build(request, Amber.settings.secret_key_base)
  end

  def session
    @session ||= Amber::Router::Session::Store.new(cookies, Amber.settings.session).build
  end

  def flash
    @flash ||= Amber::Router::Flash.from_session(session.fetch(Amber::Pipe::Flash::PARAM_KEY, "{}"))
  end

  def websocket?
    request.headers["Upgrade"]? == "websocket"
  end

  def request_handler
    route.payload
  end

  # TODO rename this method to something move descriptive
  def valve
    request_handler.valve
  end

  {% for method in METHODS %}
  def {{method.id}}?
    request.method == "{{method.id}}"
  end
  {% end %}

  def format
    Amber::Support::MimeTypes.get_request_format(request)
  end

  def port
    request.port
  end

  def requested_url
    request.url
  end

  def halt!(status_code : Int32 = 200, @content = "")
    response.headers["Content-Type"] = "text/plain"
    response.status_code = status_code
  end

  protected def invalid_route?
    !route.payload? && !router.socket_route_defined?(@request)
  end

  protected def process_websocket_request
    router.get_socket_handler(request).call(self)
  end

  protected def process_request
    request_handler.call(self)
  end

  protected def finalize_response
    response.headers["Connection"] = "Keep-Alive"
    response.headers.add("Keep-Alive", "timeout=5, max=10000")
    response.print(@content) unless request.method == "HEAD"
  end
end
