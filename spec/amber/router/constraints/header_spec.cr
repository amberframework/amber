require "../../../spec_helper"

module Amber::Router::Constraints
  describe Header do
    describe "#matches?" do
      it "matches when header has expected value" do
        constraint = Header.new("Api-Version", "v1")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Api-Version" => "v1"})
        constraint.matches?(request).should be_true
      end

      it "does not match when header value differs" do
        constraint = Header.new("Api-Version", "v1")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Api-Version" => "v2"})
        constraint.matches?(request).should be_false
      end

      it "does not match when header is missing" do
        constraint = Header.new("Api-Version", "v1")
        request = HTTP::Request.new("GET", "/")
        constraint.matches?(request).should be_false
      end
    end
  end
end
