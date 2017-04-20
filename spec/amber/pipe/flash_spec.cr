require "../../spec_helper"

module Amber
  module Pipe
    describe Flash do

      it "sets a cookie" do
        flash = Flash.instance
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)

        response = flash.call(context)

        context.response.headers.has_key?("set-cookie").should be_true
      end

      it "sets a flash message" do
        flash = Flash.instance
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash["error"] = "There was a problem"

        flash.call(context)

        context.flash["error"].should eq "There was a problem"
      end

      it "returns a list of flash messages that have not been read" do
        flash = Flash.instance
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash["error"] = "There was a problem"

        flash.call(context)

        context.flash.unread["error"].should eq "There was a problem"
      end

      it "does not return read messages" do
        flash = Flash.instance
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)
        context.flash["error"] = "There was a problem"

        flash.call(context)

        context.flash.unread["error"].should eq "There was a problem"
      end

      it "supports enumerable" do
        flash = Flash.instance
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
