# Compiled and run by spec/amber/ssl/tls_opt_in_spec.cr, once as built and
# once with -Duse_openssl, which was removed and must change nothing.
#
# What `require "amber/tls"` adds: `Amber::TLS.compiled_in?` turns true,
# `Amber::SSL#generate_tls` builds the server context from the key and
# certificate files, `Amber::TLS::Backend.bind_listener` (what
# `Amber::Server#start` calls for `server.ssl`) serves HTTPS, and the SMTP
# mailer speaks TLS 1.3 with STARTTLS or implicit TLS, verifying the mail
# server's chain and name. Only the files these need are required, so the
# build stays small enough for CI machines that also hold the suite's own
# compiler in memory; the full app path is proved by the generated-app check
# in the release evidence.
#
# Each result is printed as `key=value`.
require "../../../src/amber/server/ssl"
require "../../../src/amber/tls"
require "../../../src/amber/mailer"
require "http/client/response"

private alias BerylTLS = Amber::Beryl::TLS

# The directory make_spec_chain.sh wrote the chain into.
chain_directory = ARGV[0]
ca_file = File.join(chain_directory, "ca.pem")
chain_file = File.join(chain_directory, "localhost_chain.pem")
key_file = File.join(chain_directory, "localhost_private_key.pem")

STDOUT.puts "compiled_in=#{Amber::TLS.compiled_in?}"
STDOUT.puts "context=#{Amber::SSL.new(key_file, chain_file).generate_tls.class}"

# The HTTPS listener, reached by a client that verifies the chain to the spec
# root and the name localhost.
server = HTTP::Server.new do |context|
  context.response.print "served over TLS"
end
address = Amber::TLS::Backend.bind_listener(server, "127.0.0.1", 0, key_file, chain_file, false)
spawn(name: "tls probe server") { server.listen }

client_context = BerylTLS::Context::Client.new
client_context.ca_certificates = ca_file
client_context.alpn_protocols = ["http/1.1"]

# A client whose handshake fails first: the listener keeps serving.
plain_client = TCPSocket.new("127.0.0.1", address.port)
plain_client << "GET / HTTP/1.1\r\n\r\n"
plain_client.flush
plain_client.close

tls_socket = BerylTLS::Socket::Client.new(TCPSocket.new("127.0.0.1", address.port), client_context, sync_close: true, hostname: "localhost")
STDOUT.puts "tls_version=#{tls_socket.tls_version}"
STDOUT.puts "alpn=#{tls_socket.alpn_protocol}"
tls_socket << "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
tls_socket.flush
response = HTTP::Client::Response.from_io(tls_socket)
tls_socket.close
STDOUT.puts "status=#{response.status_code}"
STDOUT.puts "body=#{response.body}"

# A mail server on Beryl's TLS 1.3 server with the spec chain. With
# *is_implicit* TLS starts at once; otherwise after STARTTLS. Returns its
# port and a channel that receives the message data.
def start_mail_server(chain_file : String, key_file : String, is_implicit : Bool) : {Int32, Channel(String)}
  tcp_server = TCPServer.new("127.0.0.1", 0)
  context = BerylTLS::Context::Server.new
  context.certificate_chain = chain_file
  context.private_key = key_file
  received = Channel(String).new(1)
  spawn(name: "spec mail server") do
    if connection = tcp_server.accept?
      io = is_implicit ? BerylTLS::Socket::Server.new(connection, context, sync_close: true) : connection
      io << "220 spec ESMTP\r\n"
      io.flush
      message_data = String::Builder.new
      while line = io.gets
        command = line.upcase
        if command.starts_with?("EHLO")
          io << (io.is_a?(TCPSocket) ? "250-spec\r\n250 STARTTLS\r\n" : "250 spec\r\n")
        elsif command.starts_with?("STARTTLS")
          io << "220 ready\r\n"
          io.flush
          io = BerylTLS::Socket::Server.new(connection, context, sync_close: true)
          next
        elsif command.starts_with?("DATA")
          io << "354 go on\r\n"
          io.flush
          while body_line = io.gets
            break if body_line == "."
            message_data << body_line << "\n"
          end
          io << "250 queued\r\n"
        elsif command.starts_with?("QUIT")
          io << "221 bye\r\n"
          io.flush
          break
        else
          io << "250 ok\r\n"
        end
        io.flush
      end
      io.close
      received.send(message_data.to_s)
    end
  rescue error
    STDOUT.puts "mail_server_error=#{error.message}"
    received.send("")
  ensure
    tcp_server.close
  end
  {tcp_server.local_address.port, received}
end

# A mail server that offers STARTTLS but answers the ClientHello as a TLS 1.2
# server would: with *reply*, a TLS 1.2 ServerHello or a handshake_failure
# alert.
def start_tls_1_2_mail_server(reply : Bytes) : Int32
  tcp_server = TCPServer.new("127.0.0.1", 0)
  spawn(name: "spec TLS 1.2 mail server") do
    if connection = tcp_server.accept?
      connection << "220 spec ESMTP\r\n"
      connection.flush
      connection.gets
      connection << "250-spec\r\n250 STARTTLS\r\n"
      connection.flush
      connection.gets
      connection << "220 ready\r\n"
      connection.flush
      header = Bytes.new(5)
      connection.read_fully(header)
      connection.skip((header[3].to_i << 8) | header[4].to_i)
      connection.write(reply)
      connection.flush
      connection.gets
      connection.close
    end
  rescue IO::Error
  ensure
    tcp_server.close
  end
  tcp_server.local_address.port
end

email = Amber::Mailer::Email.new(to: ["recipient@example.com"], from: "sender@example.com", subject: "TLS 1.3 spec", text_body: "sent over TLS 1.3")

{false, true}.each do |is_implicit|
  label = is_implicit ? "implicit_tls" : "starttls"
  port, received = start_mail_server(chain_file, key_file, is_implicit)
  adapter = Amber::Mailer::SMTPAdapter.new(host: "localhost", port: port, use_tls: !is_implicit,
    use_implicit_tls: is_implicit, ca_certificates_file: ca_file)
  result = adapter.deliver(email)
  STDOUT.puts "#{label}=#{result.is_successful ? "delivered" : result.error}"
  STDOUT.puts "#{label}_body_seen=#{received.receive.includes?("sent over TLS 1.3")}"
end

# The certificate names localhost and 127.0.0.1 and chains to the spec root,
# which the Mozilla roots do not hold: without ca_certificates_file it is refused.
port, _ = start_mail_server(chain_file, key_file, false)
adapter = Amber::Mailer::SMTPAdapter.new(host: "127.0.0.1", port: port, use_tls: true)
result = adapter.deliver(email)
STDOUT.puts "untrusted_root=#{result.is_successful ? "delivered" : result.error}"

# random: 32 bytes; session id: empty; TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256; no compression; no extensions.
server_hello_body = Bytes[3, 3] + Bytes.new(32, 7) + Bytes[0, 0xC0, 0x2F, 0, 0, 0]
server_hello = Bytes[2, 0, 0, server_hello_body.size.to_u8] + server_hello_body
tls_1_2_server_hello = Bytes[22, 3, 3, 0, server_hello.size.to_u8] + server_hello
handshake_failure_alert = Bytes[21, 3, 3, 0, 2, 2, 40]
{"tls_1_2_server_hello" => tls_1_2_server_hello, "tls_1_2_alert" => handshake_failure_alert}.each do |label, reply|
  adapter = Amber::Mailer::SMTPAdapter.new(host: "localhost", port: start_tls_1_2_mail_server(reply), use_tls: true, ca_certificates_file: ca_file)
  result = adapter.deliver(email)
  STDOUT.puts "#{label}=#{result.is_successful ? "delivered" : result.error}"
end
