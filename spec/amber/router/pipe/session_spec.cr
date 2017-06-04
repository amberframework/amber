require "../../../../spec_helper"

module Amber
  module Pipe
    describe Session do
      it "sets a cookie" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.new

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

        cookie.should eq "key.session=404f0c34f1efcb0d96e0c801fbc0fed13db667b0--LS0tCmF1dGhvcml6ZWQ6IHRydWUK%0A; path=/"
      end

      it "uses a secret" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.new("key.session", "some-secret-key")
        session.secret =
        context.session["authorized"] = "true"

        session.call(context)
        cookie = context.response.headers["set-cookie"]

        cookie.should eq "key.session=67b626dc85fd1e1b9c91c3f459bdfcf0902051de--LS0tCmF1dGhvcml6ZWQ6IHRydWUK%0A; path=/"
      end
    end
  end
end
