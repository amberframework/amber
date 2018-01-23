require "../../../spec_helper"

module Amber
  module Pipe
    describe Session do
      it "sets a cookie" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.session[:listening] = "linkin park"
        Session.new.call(context)

        context.response.headers.has_key?("Set-Cookie").should be_true
      end

      context "session persist across different requests" do
        context "Cookies Store" do
          it "sets session value in controller" do
            request1 = HTTP::Request.new("GET", "/")
            request_1 = create_context(request1)
            request_1.session["name"] = "david"
            Session.new.call(request_1)

            request2 = HTTP::Request.new("GET", "/", request_1.response.headers)
            request_2 = create_context(request2)
            Session.new.call(request_2)

            request_2.session["name"].should eq "david"
          end
        end

        context "Redis Store" do
          it "sets session value in controller" do
            Amber.settings.session = {
              "key"     => "session_id",
              "store"   => "redis",
              "expires" => 120,
            }

            request1 = HTTP::Request.new("GET", "/")
            request_1 = create_context(request1)
            request_1.session["name"] = "david"
            request_1.session["last"] = "akward"
            Session.new.call(request_1)

            request2 = HTTP::Request.new("GET", "/", request_1.response.headers)
            request_2 = create_context(request2)
            Session.new.call(request_2)

            request_2.session["name"].should eq "david"
            request_2.session["last"].should eq "akward"
          end
        end
      end
    end
  end
end
