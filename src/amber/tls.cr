# TLS for an Amber app: the HTTPS listener (`server.ssl.key_file` and
# `server.ssl.cert_file`) and the SMTP mailer's TLS (STARTTLS with
# `smtp.use_tls`, implicit TLS with `smtp.use_implicit_tls`).
#
# Amber speaks TLS 1.3 only, on Beryl, Amber's own TLS written in Crystal, so
# an app that requires this file links no OpenSSL. A peer that cannot speak
# TLS 1.3 is refused. An app that serves HTTPS itself adds this require to
# `config/application.cr`; an app whose TLS ends at a proxy or load balancer
# leaves it out:
#
# ```
# require "amber"
# require "amber/tls"
# ```
#
# For one release, building with `-Duse_openssl` puts OpenSSL back under the
# same settings, for an app that needs to compare the two.
{% if flag?(:use_openssl) %}
  {% if flag?(:without_openssl) %}
    {% raise "-Duse_openssl and -Dwithout_openssl contradict each other. Drop -Duse_openssl to serve TLS on Beryl, which needs no OpenSSL." %}
  {% end %}
  require "openssl"
{% end %}
require "http/server"
require "./vendor/beryl"
require "./server/ssl"
require "./server/tcp_listener"

module Amber
  module TLS
    # The ALPN protocol the HTTPS listener offers. Amber serves HTTP/1.1.
    LIST_OF_ALPN_PROTOCOLS = ["http/1.1"]

    # Amber's TLS on Beryl: TLS 1.3, certificates verified against the
    # Mozilla roots (or a CA file the app names), no OpenSSL.
    module BerylBackend
      # Returns the server context for the PEM key and certificate chain
      # files.
      def self.server_context(key_file : String, cert_file : String) : Beryl::TLS::Context::Server
        context = Beryl::TLS::Context::Server.new
        context.certificate_chain = cert_file
        context.private_key = key_file
        context.alpn_protocols = LIST_OF_ALPN_PROTOCOLS
        context
      end

      # Binds *server* to *host*:*port* over TLS with the key and certificate
      # files. Each handshake runs in its connection's fiber, on its first
      # read, so a slow client never holds up the accept loop. Each accepted
      # connection gets `TCP_NODELAY` when *tcp_nodelay* is true.
      def self.bind_listener(server : HTTP::Server, host : String, port : Int32, key_file : String, cert_file : String, reuse_port : Bool, tcp_nodelay : Bool = true) : Socket::IPAddress
        context = server_context(key_file, cert_file)
        tcp_server = TCPServer.new(host, port, reuse_port: reuse_port)
        tls_server = Beryl::TLS::Server.new(tcp_server, context)
        tls_server.tcp_nodelay = tcp_nodelay
        server.bind(tls_server)
        tcp_server.local_address
      end

      # Starts TLS over *socket*, the connection to the mail server, checking
      # its certificate chain and *hostname*. The chain is verified against
      # the Mozilla roots, or against the certificates in *ca_certificates_file*
      # when one is given.
      def self.start_client_session(socket : IO, hostname : String, ca_certificates_file : String? = nil) : IO
        context = Beryl::TLS::Context::Client.new
        context.ca_certificates = ca_certificates_file if ca_certificates_file
        Beryl::TLS::Socket::Client.new(socket, context, sync_close: true, hostname: hostname)
      rescue error : Beryl::TLS::Error
        raise ClientSessionFailed.new(hostname, error.message.to_s, error.alert_description.protocol_version? ||
                                                                    error.alert_description.handshake_failure? ||
                                                                    error.alert_description.insufficient_security?)
      end
    end

    {% if flag?(:use_openssl) %}
      # OpenSSL under the same settings, kept for one release behind
      # `-Duse_openssl`. It too is held to TLS 1.3.
      module OpenSSLBackend
        # Returns the server context for the key and certificate files.
        def self.server_context(key_file : String, cert_file : String) : OpenSSL::SSL::Context::Server
          context = OpenSSL::SSL::Context::Server.new
          context.private_key = key_file
          context.certificate_chain = cert_file
          context.add_options(OpenSSL::SSL::Options::NO_TLS_V1_2)
          context.alpn_protocol = LIST_OF_ALPN_PROTOCOLS.first
          context
        end

        # Binds *server* to *host*:*port* over TLS with the key and certificate
        # files. Each accepted connection gets `TCP_NODELAY` when
        # *tcp_nodelay* is true.
        def self.bind_listener(server : HTTP::Server, host : String, port : Int32, key_file : String, cert_file : String, reuse_port : Bool, tcp_nodelay : Bool = true) : Socket::IPAddress
          listener = Amber::Server::TCPListener.new(host, port, reuse_port: reuse_port)
          listener.tcp_nodelay = tcp_nodelay
          server.bind(OpenSSL::SSL::Server.new(listener, server_context(key_file, cert_file)))
          listener.local_address
        end

        # Starts TLS on a connection to the mail server, checking the
        # certificate against *hostname*.
        def self.start_client_session(socket : IO, hostname : String, ca_certificates_file : String? = nil) : IO
          context = OpenSSL::SSL::Context::Client.new
          context.add_options(OpenSSL::SSL::Options::NO_TLS_V1_2)
          context.ca_certificates = ca_certificates_file if ca_certificates_file
          OpenSSL::SSL::Socket::Client.new(socket, context, sync_close: true, hostname: hostname)
        rescue error : OpenSSL::SSL::Error
          raise ClientSessionFailed.new(hostname, error.message.to_s, is_version_refusal?(error.message.to_s))
        end

        # Whether OpenSSL's *reason* says the server offered no TLS 1.3.
        private def self.is_version_refusal?(reason : String) : Bool
          {"unsupported protocol", "wrong version number", "handshake failure", "protocol version"}.any? { |text| reason.includes?(text) }
        end
      end

      # The backend the HTTPS listener and the mailer use.
      Backend = OpenSSLBackend
    {% else %}
      # The backend the HTTPS listener and the mailer use.
      Backend = BerylBackend
    {% end %}
  end
end
