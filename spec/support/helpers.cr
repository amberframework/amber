KEY_GENERATOR = Amber::Support::CachingKeyGenerator.new(
  Amber::Support::KeyGenerator.new("secret", 1)
)

def new_cookie_store(headers = HTTP::Headers.new)
  cookies = Amber::Router::Cookies::Store.new(KEY_GENERATOR)
  cookies.update(Amber::Router::Cookies::Store.from_headers(headers))
  cookies
end

def cookie_header(cookies)
  http_headers = HTTP::Headers.new
  cookies.write(http_headers)
  http_headers["Set-Cookie"]
end

def create_request_and_return_io(router, request)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  router.call(context)
  response.close
  io.rewind
  HTTP::Client::Response.from_io(io, decompress: false)
end

def make_router_call(router, request, token : (String | Nil) = nil)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  unless token.nil?
    context.session["csrf.token"] = token
    context.params["_csrf"] = token
  end
  router.call(context)
end

def create_context(request)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  HTTP::Server::Context.new(request, response)
end

def build_controller(referer)
  request = HTTP::Request.new("GET", "/")
  request.headers.add("Referer", referer)
  context = create_context(request)
  HelloController.new(context)
end

def create_user_socket
  ws = HTTP::WebSocket.new(STDOUT)
  client_socket = UserSocket.new(ws)
  return ws, client_socket
end
