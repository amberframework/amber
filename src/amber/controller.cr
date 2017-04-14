require "http"

module Amber
  abstract class Controller
    getter :request, :response

    getter log : ::Logger = Amber::Server.instance.log

    def set_context(@request : HTTP::Request, @response : HTTP::Server::Response)
    end
  end
end
