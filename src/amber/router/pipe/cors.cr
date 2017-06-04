module Amber
  module Pipe
    # The CORS Handler adds support for Cross Origin Resource Sharing.
    class CORS < Base
      property allow_origin, allow_headers, allow_methods, allow_credentials,
        max_age

      def initialize
        @allow_origin = "*"
        @allow_headers = "Accept, Content-Type"
        @allow_methods = "GET, HEAD, POST, DELETE, OPTIONS, PUT, PATCH"
        @allow_credentials = false
        @max_age = 0
      end

      def call(context : HTTP::Server::Context)
        begin
          context.response.headers["Access-Control-Allow-Origin"] = allow_origin

          # TODO: verify the actual origin matches allowed origins.
          # if requested_origin = context.request.headers["Origin"]
          #   if allow_origins.includes? requested_origin
          #   end
          # end

          if allow_credentials
            context.response.headers["Access-Control-Allow-credentials"] = "true"
          end

          if max_age > 0
            context.response.headers["Access-Control-Max-Age"] = max_age.to_s
          end

          # if asking permission for request method or request headers
          if context.request.method.downcase == "options"
            context.response.status_code = 200
            response = ""

            if requested_method = context.request.headers["Access-Control-Request-Method"]
              if allow_methods.includes? requested_method.strip
                context.response.headers["Access-Control-Allow-Methods"] = allow_methods
              else
                context.response.status_code = 403
                response = "Method #{requested_method} not allowed."
              end
            end

            if requested_headers = context.request.headers["Access-Control-Request-Headers"]
              requested_headers.split(",").each do |requested_header|
                if allow_headers.includes? requested_header.strip
                  context.response.headers["Access-Control-Allow-Headers"] = allow_headers
                else
                  context.response.status_code = 403
                  response = "Headers #{requested_headers} not allowed."
                end
              end
            end

            context.response.content_type = "text/html; charset=utf-8"
            context.response.print(response)
          else
            call_next(context)
          end
        end
      end
    end
  end
end
