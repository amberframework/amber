require "../../../spec_helper"

module Amber::Router::Constraints
  describe Host do
    describe "#matches?" do
      it "matches when host header matches exactly" do
        constraint = Host.new("example.com")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Host" => "example.com"})
        constraint.matches?(request).should be_true
      end

      it "matches when host header includes port" do
        constraint = Host.new("example.com")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Host" => "example.com:3000"})
        constraint.matches?(request).should be_true
      end

      it "does not match when host differs" do
        constraint = Host.new("example.com")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Host" => "other.com"})
        constraint.matches?(request).should be_false
      end

      it "does not match when no host header" do
        constraint = Host.new("example.com")
        request = HTTP::Request.new("GET", "/")
        constraint.matches?(request).should be_false
      end
    end
  end
end
