module Amber
    class Request
        getter method, path, handler
        @handler : HTTP::Server::Context -> String
        @http_verb : String

        def initialize(@http_verb, @path : String, &handler : HTTP::Server::Context -> _)
        @handler = ->(context : HTTP::Server::Context) do
            handler.call(context).to_s
        end
    end
end
