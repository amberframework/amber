module Amber
   class Request
    getter path
    getter version
    getter params
    getter cookies
    getter content_type

    def initialize(request : HTTP::Request)
        @path = request.path.not_nil!
        @query = request.query
        @version = request.version
        @headers = request.headers
        @cookies = {} of String => String
        @content_type = request.headers["Content-type"]? || ""
        @params = Hash(String, String).new
    end

    def initialize(request : HTTP::Request, params)
        initialize(request)
        @params = params ? params.not_nil! : Hash(String, String).new
    end

    # Adds parameters from param string
    def add_params_from_string(params_string)
        params = params_string.split("&")
        return if params.size < 1
        params.each do |x|
        par = x.split("=")
        next if par.size < 2
        key = URI.unescape(par[0])
        val = URI.unescape(par[1])
        @params[key] = val
        end
    end
    end
end
