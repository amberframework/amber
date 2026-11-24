require "../../spec_helper"

# The suite does not require "amber/tls", so it runs as a generated app does
# by default: no TLS, and no OpenSSL from Amber. spec/amber/ssl/tls_opt_in_spec.cr
# builds an app that requires it.
module Amber
  describe SSL do
    it "raises TLSNotCompiledIn, naming require \"amber/tls\", when the app does not require it" do
      expect_raises(Amber::Exceptions::TLSNotCompiledIn, %(require "amber/tls")) do
        SSL.new(File.join(__DIR__, "key.pem"), File.join(__DIR__, "cert.pem")).generate_tls
      end
    end
  end

  describe TLS do
    it "is not compiled in unless the app requires amber/tls" do
      TLS.compiled_in?.should be_false
    end
  end
end
