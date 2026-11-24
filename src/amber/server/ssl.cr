module Amber
  # Builds the TLS context of the HTTPS listener from the configured key and
  # certificate files.
  #
  # TLS is opt-in: an app that serves HTTPS itself (`server.ssl.key_file` and
  # `server.ssl.cert_file`) or sends mail over SMTP STARTTLS adds
  # `require "amber/tls"`. Without it the app links no OpenSSL, and
  # `generate_tls` raises `Amber::Exceptions::TLSNotCompiledIn`, which names
  # that require.
  class SSL
    def initialize(@key_file : String, @cert_file : String)
    end

    # Returns the `OpenSSL::SSL::Context::Server` for the key and certificate
    # files when the app requires `amber/tls`.
    def generate_tls
      # Expanded when this method is instantiated, after every file is
      # required, so `require "amber/tls"` may come before or after
      # `require "amber"`.
      {% if Amber::TLS.has_constant?(:OpenSSLBackend) %}
        Amber::TLS::OpenSSLBackend.server_context(@key_file, @cert_file)
      {% else %}
        raise Amber::Exceptions::TLSNotCompiledIn.new(Amber::TLS::LISTENER)
      {% end %}
    end
  end

  # Whether this app was built with TLS. `require "amber/tls"` adds
  # `Amber::TLS::OpenSSLBackend`, which the HTTPS listener and SMTP STARTTLS
  # use; an app without it links no OpenSSL.
  module TLS
    # The feature names `Amber::Exceptions::TLSNotCompiledIn` reports.
    LISTENER = "The HTTPS listener (server.ssl.key_file and server.ssl.cert_file)"
    STARTTLS = "SMTP STARTTLS (mailer smtp use_tls)"

    # Returns `true` when the app requires `amber/tls`.
    def self.compiled_in? : Bool
      {% if Amber::TLS.has_constant?(:OpenSSLBackend) %}
        true
      {% else %}
        false
      {% end %}
    end
  end
end
