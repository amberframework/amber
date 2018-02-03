require "json"

module Amber::Router
  # The Parameters module will parse parameters from a URL, a form post or a JSON
  # post and provide them in the self params hash.  This unifies access to
  # parameters into one place to simplify access to them.
  # Note: other params from the router will be handled in the router handler
  # instead of here.  This removes a dependency on the router in case it is
  # replaced or not needed.
  module ParamsParser
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"
    METHOD           = "_method"
    OVERRIDE_HEADER  = "X-HTTP-Method-Override"
    OVERRIDE_METHODS = %w(PATCH PUT DELETE)
    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX

    property params = Amber::Router::Params.new

    @override_method : String?

    def clear_params
      @params = Router::Params.new
    end

    def parse_params
      parse_part(request.query)
      if content_type = request.headers["Content-Type"]?
        parse_multipart if content_type.try(&.starts_with?(MULTIPART_FORM))
        parse_part(request.body) if content_type.try(&.starts_with?(URL_ENCODED_FORM))
        parse_json if content_type.includes?(APPLICATION_JSON) && request.body
      end
    end

    # Adds Request Method Override support to the framework.
    # Param supported
    # - *_method* can be passed as a form or url param
    #
    # HTTP Headers supported:
    # - *X-HTTP-Method-Override* (Google/GData)
    #
    # The convention has been established that the GET and HEAD methods SHOULD NOT
    # have the significance of taking an action other than retrieval.
    #
    # These methods ought to be considered "safe". This allows user agents to
    # represent other methods, such as POST, PUT and DELETE, in a special way,
    # so that the user is made aware of the fact that a possibly unsafe action
    # is being requested.
    #
    # Read RFC 2616 - HTTP 1.1 section 9.1.1
    # (https://tools.ietf.org/html/rfc2616#section-9.1)
    #
    # In other words, if you are tempted to use a GET to simulate a PUT or DELETE,
    # don't do it. Use a POST instead.
    def override_request_method!
      # If the current request method is not GET or POST it means that it was
      # already overridden
      return unless %(GET POST).includes? request.method
      if (method = override_method) && override_method?
        request.method = method
      end
    end

    # Determines the existence of HTTP Request Method Override in headers
    def override_header?
      request.headers[OVERRIDE_HEADER]?
    end

    private def override_method?
      OVERRIDE_METHODS.includes? override_method
    end

    private def override_method
      @override_method ||= (params[METHOD]? || override_header?).try &.to_s.upcase
    end

    def merge_route_params
      route_params_without_ext.each do |k, v|
        params[k] = v
      end
    end

    def route_params_without_ext
      rparams = route.params
      unless rparams.empty?
        key = rparams.keys.last
        rparams[key] = rparams[key].sub(TYPE_EXT_REGEX, "")
      end
      route.params
    end

    def route_params
      route.params
    end

    def parse_json
      if body = request.body.not_nil!.gets_to_end
        if body.size > 2
          case json = JSON.parse_raw(body)
          when Hash
            json.each do |key, value|
              if value.is_a?(String)
                params[key.as(String)] = value
              else
                params[key.as(String)] = value.to_json
              end
            end
          when Array
            params["_json"] = json.to_json
          end
        end
      end
    end

    def parse_multipart
      HTTP::FormData.parse(request) do |upload|
        next unless upload
        # Note:
        # Filename is followed by a string containing the original name of the file transmitted.
        # The filename is always optional and must not be used blindly by the application:
        # path information should be stripped, and conversion to the server file system rules
        # should be done. This parameter provides mostly indicative information.
        #
        # See https://tools.ietf.org/html/rfc7578#section-4.2
        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          params.files[upload.name] = Amber::Router::File.new(upload: upload)
        else
          # Parses form fields
          params[upload.name] = upload.body.gets_to_end
        end
      end
    end

    private def parse_part(part)
      values = case part
               when IO
                 part.gets_to_end
               when String
                 part.to_s
               else
                 ""
               end

      HTTP::Params.parse(values) do |key, value|
        params[key] = value
      end
    end
  end
end
