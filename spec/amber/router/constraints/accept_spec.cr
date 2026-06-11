require "../../../spec_helper"

module Amber::Router::Constraints
  describe Accept do
    describe "#matches?" do
      it "matches when Accept header contains versioned media type" do
        constraint = Accept.new("application/vnd.myapp", "v1")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Accept" => "application/vnd.myapp.v1+json"})
        constraint.matches?(request).should be_true
      end

      it "does not match when version differs" do
        constraint = Accept.new("application/vnd.myapp", "v1")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Accept" => "application/vnd.myapp.v2+json"})
        constraint.matches?(request).should be_false
      end

      it "does not match when media type differs" do
        constraint = Accept.new("application/vnd.myapp", "v1")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Accept" => "application/vnd.other.v1+json"})
        constraint.matches?(request).should be_false
      end

      it "does not match when Accept header is missing" do
        constraint = Accept.new("application/vnd.myapp", "v1")
        request = HTTP::Request.new("GET", "/")
        constraint.matches?(request).should be_false
      end

      it "matches with different format suffixes" do
        constraint = Accept.new("application/vnd.myapp", "v1")
        request = HTTP::Request.new("GET", "/", HTTP::Headers{"Accept" => "application/vnd.myapp.v1+xml"})
        constraint.matches?(request).should be_true
      end
    end
  end
end
