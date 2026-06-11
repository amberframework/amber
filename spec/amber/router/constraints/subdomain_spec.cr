require "../../../spec_helper"

module Amber::Router::Constraints
  describe Subdomain do
    describe "#matches?" do
      it "matches when host starts with subdomain" do
        constraint = Subdomain.new("admin")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Host" => "admin.example.com"})
        constraint.matches?(request).should be_true
      end

      it "matches with port in host header" do
        constraint = Subdomain.new("api")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Host" => "api.example.com:3000"})
        constraint.matches?(request).should be_true
      end

      it "does not match when subdomain differs" do
        constraint = Subdomain.new("admin")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Host" => "api.example.com"})
        constraint.matches?(request).should be_false
      end

      it "does not match when host has no subdomain" do
        constraint = Subdomain.new("admin")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Host" => "example.com"})
        constraint.matches?(request).should be_false
      end

      it "does not match when no host header" do
        constraint = Subdomain.new("admin")
        request = HTTP::Request.new("GET", "/")
        constraint.matches?(request).should be_false
      end
    end
  end
end
