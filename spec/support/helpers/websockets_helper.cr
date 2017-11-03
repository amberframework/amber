module WebsocketsHelper
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
end
