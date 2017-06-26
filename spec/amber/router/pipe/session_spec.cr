require "../../../../spec_helper"

module Amber
  module Pipe
    describe Session do
      it "sets a cookie" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.new
        session.next = -> (context : HTTP::Server::Context){context.session["test"] = "test"}
        session.call(context)

        context.response.headers.has_key?("set-cookie").should be_true
      end

      it "encodes the session data" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.new("key.session", "some-secret-key")
        context.session["authorized"] = "true"

        session.call(context)
        cookie = context.response.headers["set-cookie"]

        cookie.should eq "key.session=8a45be69c9e296834650a6e73c50f931a60d6cf8--eyJhdXRob3JpemVkIjoidHJ1ZSJ9%0A; path=/"
      end

      it "uses a secret" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.new("key.session", "some-secret-key")
        context.session["authorized"] = "true"

        session.call(context)
        cookie = context.response.headers["set-cookie"]

        cookie.should eq "key.session=8a45be69c9e296834650a6e73c50f931a60d6cf8--eyJhdXRob3JpemVkIjoidHJ1ZSJ9%0A; path=/"
      end
    end
  end
end
