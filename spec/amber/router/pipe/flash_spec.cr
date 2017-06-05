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

        context.response.headers.has_key?("set-cookie").should be_true
      end

      it "sets a flash message" do
        flash = Flash.new
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash["error"] = "There was a problem"

        flash.call(context)

        context.flash["error"].should eq "There was a problem"
      end

      it "returns a list of flash messages that have not been read" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash[:error] = "There was a problem"
        unread = context.flash.unread
        unread["error"]?.should eq "There was a problem"
      end

      it "does not return read messages" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash["error"] = "There was a problem"
        context.flash[:error]
        context.flash.unread["error"]?.should_not eq "There was a problem"
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
