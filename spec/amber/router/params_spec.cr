require "../../../spec_helper"

module Amber::Router
  describe Parse do
    context "when parsing query string" do
      it "returns query params" do
        request = HTTP::Request.new("GET", "/?test=test")
        params = Parse.new(request).parse
        params["test"].should eq "test"
      end

      it "returns array of values for same param key" do
        request = HTTP::Request.new("GET", "/?test=test&test=test2")
        params = Parse.new(request).parse
        params.fetch_all("test").size.should eq 2
        params.fetch_all("test").should eq %w(test test2)
      end
    end
  end
end