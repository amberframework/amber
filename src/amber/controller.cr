require "http"

module Amber
  abstract class Controller
    getter :request, :response

    def set_context(@request : HTTP::Request, @response : HTTP::Server::Response)
    end
  end
end
