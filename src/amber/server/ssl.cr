{% unless flag?(:without_openssl) %}
  require "openssl"
{% end %}

module Amber
  # Builds the TLS context of the HTTPS listener from the configured key and
  # certificate files.
  #
  # TLS comes from OpenSSL. A build made with `-Dwithout_openssl` links no
  # OpenSSL and has no TLS listener: `generate_tls` then raises
  # `Amber::Exceptions::TLSNotCompiledIn`, which names the flag.
  class SSL
    def initialize(@key_file : String, @cert_file : String)
    end

    {% if flag?(:without_openssl) %}
      def generate_tls : NoReturn
        raise Amber::Exceptions::TLSNotCompiledIn.new("the HTTPS listener (server.ssl.key_file and server.ssl.cert_file)")
      end
    {% else %}
      def generate_tls
        tls = OpenSSL::SSL::Context::Server.new
        tls.private_key = @key_file
        tls.certificate_chain = @cert_file
        tls
      end
    {% end %}
  end
end
