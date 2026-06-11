require "./base"

module Amber
  module Pipe
    # Middleware that extracts an API version from request headers
    # and normalizes it into a standard internal header for downstream use.
    #
    # Usage in pipeline configuration:
    #   Amber::Server.instance.pipeline :api do
    #     plug Amber::Pipe::ApiVersion.new(default_version: "v1")
    #   end
    #
    # Controllers can then access the version:
    #   request.headers["X-Api-Version"]?
    class ApiVersion < Base
      def initialize(@header : String = "Api-Version", @default_version : String? = nil)
      end

      def call(context : HTTP::Server::Context)
        version = context.request.headers[@header]? || @default_version
        if version
          context.request.headers["X-Api-Version"] = version
        end
        call_next(context)
      end
    end
  end
end
