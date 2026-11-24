# Compiled and run by spec/amber/ssl/tls_opt_in_spec.cr.
#
# What `require "amber/tls"` adds: `Amber::TLS.compiled_in?` turns true,
# `Amber::SSL#generate_tls` builds the server context from the key and
# certificate files, and `Amber::TLS::OpenSSLBackend.bind_listener` (what
# `Amber::Server#start` calls for `server.ssl`) serves HTTPS. Only those two
# files are required, so the build stays small enough for CI machines that
# also hold the suite's own compiler in memory; the full app path is proved
# by the generated-app check in the release evidence.
require "../../../src/amber/server/ssl"
require "../../../src/amber/tls"
require "http/client/response"

key_file, cert_file = ARGV[0], ARGV[1]

STDOUT.puts "compiled_in=#{Amber::TLS.compiled_in?}"
STDOUT.puts "context=#{Amber::SSL.new(key_file, cert_file).generate_tls.class}"

server = HTTP::Server.new do |context|
  context.response.print "served over TLS"
end
address = Amber::TLS::OpenSSLBackend.bind_listener(server, "127.0.0.1", 0, key_file, cert_file, false)
spawn(name: "tls probe server") { server.listen }

# The spec certificate is self-signed, so the client skips verification.
client_context = OpenSSL::SSL::Context::Client.insecure
100.times do
  tcp_socket = TCPSocket.new("127.0.0.1", address.port)
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
