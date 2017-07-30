require "../../../spec_helper"

module Amber
  describe SSL do
    it "generates tls" do
      tls = SSL.new(File.join(__DIR__, "key.pem"), File.join(__DIR__, "cert.pem")).generate_tls
      tls.should be_a(OpenSSL::SSL::Context::Server)
    end
  end
end
