require "../../../../spec_helper"

module Amber
  module Pipe
    describe Session do
      it "sets a cookie" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.instance
        session.call(context)
        context.response.headers.has_key?("set-cookie").should be_true
      end

      it "encodes the session data" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.instance
        session.secret = "some-secret-key"
        context.session["authorized"] = "true"
        session.call(context)
        cookie = context.response.headers["set-cookie"]
        cookie.should eq "#{Amber::Server.settings.project_name}.session=404f0c34f1efcb0d96e0c801fbc0fed13db667b0--LS0tCmF1dGhvcml6ZWQ6IHRydWUK%0A; path=/"
      end

      it "uses a secret" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        session = Session.instance
        session.secret = "some-secret-key"
        context.session["authorized"] = "true"
        session.call(context)
        cookie = context.response.headers["set-cookie"]
        cookie.should eq "#{Amber::Server.settings.project_name}.session=404f0c34f1efcb0d96e0c801fbc0fed13db667b0--LS0tCmF1dGhvcml6ZWQ6IHRydWUK%0A; path=/"
      end
    end
  end
end
