require "../../../../spec_helper"

module Amber
  module Pipe
    describe Reload do
      it "client should contain injected code" do
        reload = Reload.new
        pipeline = Pipeline.new
        request = HTTP::Request.new("GET", "/reload")

        Amber::Server.router.draw :web do
          get "/reload", HelloController, :index
        end

        pipeline.build :web do
          plug Amber::Pipe::Reload.new
        end

        reload.next = ->(context : HTTP::Server::Context) { "Hello World!" }
        response = create_request_and_return_io(reload, request)

        response.body.should contain "Code injected by Amber Framework"
      end
    end
  end
end