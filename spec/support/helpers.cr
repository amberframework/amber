def new_cookie_store(headers = HTTP::Headers.new)
  cookies = Amber::Router::Cookies::Store.new
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

def build_controller(referer = "")
  request = HTTP::Request.new("GET", "/")
  request.headers.add("Referer", referer)
  context = create_context(request)
  HelloController.new(context)
end

def create_user_socket
  request = HTTP::Request.new("GET", "/")
  ws = HTTP::WebSocket.new(STDOUT)
  client_socket = UserSocket.new(ws, create_context(request))
  return ws, client_socket
end

def create_socket_server
  port_chan = Channel(Int32).new
  http_ref = nil

  spawn do
    handler = Amber::WebSockets::Server.create_endpoint("/", UserSocket)
    http_server = http_ref = HTTP::Server.new(0, [handler])
    http_server.bind
    port_chan.send(http_server.port)
    http_server.listen
  end

  listen_port = port_chan.receive
  ws = HTTP::WebSocket.new("ws://127.0.0.1:#{listen_port}")
  spawn { ws.run }
  return http_ref.not_nil!, ws
end
