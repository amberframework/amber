require "http"
require "json"

module Amber::Testing
  # Builds HTTP::Server::Context objects for testing without a real HTTP server.
  # Uses a builder pattern so you can chain calls to configure the request
  # before calling `build` to produce the context.
  #
  # ```
  # context = Amber::Testing::ContextBuilder.new
  #   .method("POST")
  #   .path("/users")
  #   .header("Content-Type", "application/json")
  #   .json_body({name: "Alice"})
  #   .build
  # ```
  class ContextBuilder
    @method : String = "GET"
    @path : String = "/"
    @headers : HTTP::Headers = HTTP::Headers.new
    @body : String = ""
    @query_params : Hash(String, String) = {} of String => String

    def initialize
    end

    # Set the HTTP method (GET, POST, PUT, PATCH, DELETE, etc.)
    def method(m : String) : self
      @method = m.upcase
      self
    end

    # Set the request path.
    def path(p : String) : self
      @path = p
      self
    end

    # Add a single header to the request.
    def header(key : String, value : String) : self
      @headers[key] = value
      self
    end

    # Set the request body as a raw string.
    def body(b : String) : self
      @body = b
      self
    end

    # Set the request body as JSON and automatically set the Content-Type header.
    def json_body(data) : self
      @headers["Content-Type"] = "application/json"
      @body = data.to_json
      self
    end

    # Add a query parameter that will be appended to the path.
    def query_param(key : String, value : String) : self
      @query_params[key] = value
      self
    end

    # Add multiple query parameters from a hash.
    def params(p : Hash(String, String)) : self
      p.each { |k, v| @query_params[k] = v }
      self
    end

    # Build and return the HTTP::Server::Context.
    # The context is backed by an IO::Memory so the response can be
    # read back after processing.
    def build : HTTP::Server::Context
      full_path = build_path_with_query_params
      request = HTTP::Request.new(@method, full_path, @headers, @body)
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      HTTP::Server::Context.new(request, response)
    end

    # Build and return a tuple of {context, io} so callers can
    # read the raw response bytes from the IO after processing.
    def build_with_io : {HTTP::Server::Context, IO::Memory}
      full_path = build_path_with_query_params
      request = HTTP::Request.new(@method, full_path, @headers, @body)
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)
      {context, io}
    end

    private def build_path_with_query_params : String
      return @path if @query_params.empty?

      separator = @path.includes?('?') ? '&' : '?'
      query_string = HTTP::Params.encode(@query_params)
      "#{@path}#{separator}#{query_string}"
    end
  end
end
