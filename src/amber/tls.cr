# TLS for an Amber app, from OpenSSL: the HTTPS listener
# (`server.ssl.key_file` and `server.ssl.cert_file`) and SMTP STARTTLS
# (mailer `smtp.use_tls`).
#
# An app that serves HTTPS itself adds this require to
# `config/application.cr`; an app whose TLS ends at a proxy or load balancer
# leaves it out and links no OpenSSL:
#
# ```
# require "amber"
# require "amber/tls"
# ```
{% if flag?(:without_openssl) %}
  {% raise "require \"amber/tls\" needs OpenSSL, and this build passes -Dwithout_openssl. Remove the flag to serve HTTPS or send mail over STARTTLS." %}
{% end %}

require "openssl"
require "http/server"

module Amber
  module TLS
    # The OpenSSL side of Amber's TLS. Its presence is what
    # `Amber::TLS.compiled_in?` reports.
    module OpenSSLBackend
      # Returns the server context for the key and certificate files.
      def self.server_context(key_file : String, cert_file : String) : OpenSSL::SSL::Context::Server
        context = OpenSSL::SSL::Context::Server.new
        context.private_key = key_file
        context.certificate_chain = cert_file
        context
      end

      # Binds *server* to *host*:*port* over TLS with the key and certificate
      # files.
      def self.bind_listener(server : HTTP::Server, host : String, port : Int32, key_file : String, cert_file : String, reuse_port : Bool) : Socket::IPAddress
        server.bind_tls(host, port, server_context(key_file, cert_file), reuse_port)
      end

      # Starts TLS on an SMTP connection after the server accepted STARTTLS,
      # checking the certificate against *hostname*.
      def self.start_client_session(socket : IO, hostname : String) : IO
        OpenSSL::SSL::Socket::Client.new(socket, OpenSSL::SSL::Context::Client.new, hostname: hostname)
      end
    end
  end
end
