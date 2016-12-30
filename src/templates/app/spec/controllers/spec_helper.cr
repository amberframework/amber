require "../spec_helper"

def create_context(request)
  io = MemoryIO.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  return io, context
end
