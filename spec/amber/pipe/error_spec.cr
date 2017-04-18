
require "./../../spec_helper"

describe Amber::Pipe::Error do

  it "handles route not found exception" do
    request = HTTP::Request.new("GET", "/")
    io, context = create_context(request)
    error = Error.instance
    error.next = Router.new
    error.call(context)
    context.response.status_code.should eq 404

  end

  it "handles all other exceptions" do
    request = HTTP::Request.new("GET", "/")
    io, context = create_context(request)
    error = Error.instance
    error.next = ->(c : HTTP::Server::Context) { raise "Oh no!"}
    error.call(context)
    context.response.status_code.should eq 500
  end

end

