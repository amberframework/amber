module WebsocketsHelper
  def create_user_socket
    request = HTTP::Request.new("GET", "/")
    ws = HTTP::WebSocket.new(STDOUT)
    client_socket = UserSocket.new(ws, create_context(request))
    return ws, client_socket
  end

  def create_socket_server
    channel = Channel(Int32).new
    http_server = nil

    spawn do
      handler = Amber::WebSockets::Server.create_endpoint("/", UserSocket)
      http_server = server = HTTP::Server.new(handler)
      address = server.bind_unused_port
      channel.send(address.port)
      server.listen
    end

    listen_port = channel.receive
    ws = HTTP::WebSocket.new("ws://127.0.0.1:#{listen_port}")
    spawn { ws.run }
    return http_server.not_nil!, ws
  end
end
