require "../../spec_helper"

module Amber::Pipe
  describe ApiVersion do
    describe "#call" do
      it "extracts version from default header" do
        pipe = ApiVersion.new
        pipe.next = ->(ctx : HTTP::Server::Context) { }

        request = HTTP::Request.new("GET", "/api/users", HTTP::Headers{"Api-Version" => "v2"})
        io = IO::Memory.new
        response = HTTP::Server::Response.new(io)
        context = HTTP::Server::Context.new(request, response)

        pipe.call(context)

        context.request.headers["X-Api-Version"].should eq "v2"
      end

      it "extracts version from custom header" do
        pipe = ApiVersion.new(header: "X-Custom-Version")
        pipe.next = ->(ctx : HTTP::Server::Context) { }

        request = HTTP::Request.new("GET", "/api/users", HTTP::Headers{"X-Custom-Version" => "v3"})
        io = IO::Memory.new
        response = HTTP::Server::Response.new(io)
        context = HTTP::Server::Context.new(request, response)

        pipe.call(context)

        context.request.headers["X-Api-Version"].should eq "v3"
      end

      it "uses default version when header is missing" do
        pipe = ApiVersion.new(default_version: "v1")
        pipe.next = ->(ctx : HTTP::Server::Context) { }

        request = HTTP::Request.new("GET", "/api/users")
        io = IO::Memory.new
        response = HTTP::Server::Response.new(io)
        context = HTTP::Server::Context.new(request, response)

        pipe.call(context)

        context.request.headers["X-Api-Version"].should eq "v1"
      end

      it "does not set header when no version and no default" do
        pipe = ApiVersion.new
        pipe.next = ->(ctx : HTTP::Server::Context) { }

        request = HTTP::Request.new("GET", "/api/users")
        io = IO::Memory.new
        response = HTTP::Server::Response.new(io)
        context = HTTP::Server::Context.new(request, response)

        pipe.call(context)

        context.request.headers["X-Api-Version"]?.should be_nil
      end

      it "prefers explicit header over default" do
        pipe = ApiVersion.new(default_version: "v1")
        pipe.next = ->(ctx : HTTP::Server::Context) { }

        request = HTTP::Request.new("GET", "/api/users", HTTP::Headers{"Api-Version" => "v2"})
        io = IO::Memory.new
        response = HTTP::Server::Response.new(io)
        context = HTTP::Server::Context.new(request, response)

        pipe.call(context)

        context.request.headers["X-Api-Version"].should eq "v2"
      end
    end
  end
end
