# Compiled and run by spec/amber/ssl/tls_opt_in_spec.cr.
#
# An app that serves HTTPS itself: it requires `amber/tls`, sets the
# `server.ssl` files and starts the server the way a generated app does, then
# fetches its own page over TLS.
require "../../../src/amber"
require "../../../src/amber/tls"
require "http/client/response"

# Settings load on first use, and Amber::Server.configure below is the first.
config_path, key_file, cert_file = ARGV[0], ARGV[1], ARGV[2]
ENV["AMBER_ENV"] = "tls_probe"
Amber.path = config_path

class TLSProbeController < Amber::Controller::Base
  def index
    "served over TLS"
  end
end

Amber::Server.configure do
  pipeline :web do
    plug Amber::Pipe::Error.new
  end

  routes :web do
    get "/", TLSProbeController, :index
  end
end

free_port_probe = TCPServer.new("127.0.0.1", 0)
port = free_port_probe.local_address.port
free_port_probe.close

settings = Amber.settings
settings.host = "127.0.0.1"
settings.port = port
settings.ssl_key_file = key_file
settings.ssl_cert_file = cert_file

STDOUT.puts "compiled_in=#{Amber::TLS.compiled_in?}"
STDOUT.puts "scheme=#{Amber::Server.instance.scheme}"
STDOUT.flush

spawn(name: "tls probe server") { Amber::Server.start }

# The spec certificate is self-signed, so the client skips verification. A raw
# TLS socket keeps HTTP::Client, and the compiler memory it costs, out of the build.
client_context = OpenSSL::SSL::Context::Client.insecure
100.times do
  tcp_socket = TCPSocket.new("127.0.0.1", port)
  tls_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, client_context, sync_close: true)
  tls_socket << "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
  tls_socket.flush
  response = HTTP::Client::Response.from_io(tls_socket)
  tls_socket.close
  STDOUT.puts "status=#{response.status_code}"
  STDOUT.puts "body=#{response.body}"
  exit 0
rescue Socket::ConnectError
  sleep 50.milliseconds
end

STDOUT.puts "error=the HTTPS listener never accepted a connection"
exit 1
