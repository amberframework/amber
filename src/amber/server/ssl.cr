module Amber
  # Builds the TLS context of the HTTPS listener from the configured key and
  # certificate files.
  #
  # TLS is opt-in: an app that serves HTTPS itself (`server.ssl.key_file` and
  # `server.ssl.cert_file`) or sends mail over SMTP TLS adds
  # `require "amber/tls"`, which serves TLS 1.3 on Beryl. Without it, and
  # `generate_tls` raises `Amber::Exceptions::TLSNotCompiledIn`, which names
  # that require.
  class SSL
    def initialize(@key_file : String, @cert_file : String)
    end

    # Returns the server context for the key and certificate files when the
    # app requires `amber/tls`: a `Beryl::TLS::Context::Server`, or an
    # `OpenSSL::SSL::Context::Server` in a build with `-Duse_openssl`.
    def generate_tls
      # Expanded when this method is instantiated, after every file is
      # required, so `require "amber/tls"` may come before or after
      # `require "amber"`.
      {% if Amber::TLS.has_constant?(:Backend) %}
        Amber::TLS::Backend.server_context(@key_file, @cert_file)
      {% else %}
        raise Amber::Exceptions::TLSNotCompiledIn.new(Amber::TLS::LISTENER)
      {% end %}
    end
  end

  # Whether this app was built with TLS. `require "amber/tls"` adds
  # `Amber::TLS::Backend`, which the HTTPS listener and the SMTP mailer's TLS
  # use.
  module TLS
    # The feature names `Amber::Exceptions::TLSNotCompiledIn` reports.
    LISTENER = "The HTTPS listener (server.ssl.key_file and server.ssl.cert_file)"
    STARTTLS = "SMTP STARTTLS or implicit TLS (mailer smtp use_tls or use_implicit_tls)"

    # The TLS 1.3 requirement, as `Amber::Mailer::SMTPAdapter` reports it
    # when a mail server cannot meet it.
    TLS_1_3_REQUIREMENT = "Amber speaks TLS 1.3 only (RFC 8446); the mail server must offer TLS 1.3"

    # A TLS session with a mail server could not start. `is_version_refused?`
    # tells that the server offered no TLS 1.3, and the message then states
    # the requirement.
    class ClientSessionFailed < Exception
      getter? is_version_refused : Bool

      def initialize(hostname : String, reason : String, @is_version_refused : Bool)
        if @is_version_refused
          super("TLS with #{hostname} failed: #{TLS_1_3_REQUIREMENT}, and it did not (#{reason})")
        else
          super("TLS with #{hostname} failed: #{reason}")
        end
      end
    end

    # Returns `true` when the app requires `amber/tls`.
    def self.compiled_in? : Bool
      {% if Amber::TLS.has_constant?(:Backend) %}
        true
      {% else %}
        false
      {% end %}
    end
  end
end
