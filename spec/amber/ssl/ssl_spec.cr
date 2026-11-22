require "../../spec_helper"

module Amber
  describe SSL do
    {% if flag?(:without_openssl) %}
      it "raises TLSNotCompiledIn, naming the flag, in a build without OpenSSL" do
        expect_raises(Amber::Exceptions::TLSNotCompiledIn, "-Dwithout_openssl") do
          SSL.new(File.join(__DIR__, "key.pem"), File.join(__DIR__, "cert.pem")).generate_tls
        end
      end
    {% else %}
      it "generates tls" do
        tls = SSL.new(File.join(__DIR__, "key.pem"), File.join(__DIR__, "cert.pem")).generate_tls
        tls.should be_a(OpenSSL::SSL::Context::Server)
      end
    {% end %}
  end
end
