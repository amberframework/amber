require "../../../../spec_helper"
require "json"

module Amber
  module Pipe
    describe Flash do
      it "sets a cookie" do
        flash = Flash.new
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)

        response = flash.call(context)

        context.response.headers.has_key?("Set-Cookie").should be_true
      end

      context "between requests" do
        it "displays flash message" do
          flash = Flash.new
          request = HTTP::Request.new("GET", "/")
          context = create_context(request)

          context.flash["error"] = "Some error message"
          context2 = flash.call(context)

          context2.flash["error"].should eq "Some error message"
        end
      end

      it "sets a flash message" do
        flash = Flash.new
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash["error"] = "There was a problem"

        flash.call(context)

        context.flash["error"].should eq "There was a problem"
      end

      it "supports enumerable" do
        flash = Flash.new
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash["error"] = "There was a problem"
        context.flash["notice"] = "This is important"

        flash.call(context)

        context.flash["error"].should eq "There was a problem"
        context.flash["notice"].should eq "This is important"
      end
    end
  end
end
