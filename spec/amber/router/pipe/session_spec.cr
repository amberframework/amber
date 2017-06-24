require "../../../../spec_helper"

module Amber
  module Pipe
    describe Session do
      it "sets a cookie" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)

        Session.new.call(context)

        context.response.headers.has_key?("set-cookie").should be_true
      end
    end
  end
end
