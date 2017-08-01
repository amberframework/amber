require "openssl"

module Amber
  class SSL
    def initialize(@key_file : String, @cert_file : String)
    end

    def generate_tls
      tls = OpenSSL::SSL::Context::Server.new
      tls.private_key = @key_file
      tls.certificate_chain = @cert_file
      tls
    end
  end
end
