require "json"

module Amber::Router
  # The Params module will parse parameters from a URL, a form post or a JSON
  # post and provide them in the self params hash.  This unifies access to
  # parameters into one place to simplify access to them.
  # Note: other params from the router will be handled in the router handler
  # instead of here.  This removes a dependency on the router in case it is
  # replaced or not needed.
  module Params
    property params = HTTP::Params.new({} of String => Array(String))
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"
    METHOD           = "_method"
    OVERRIDE_METHODS = %w(patch put delete)

    alias ParamTypes = Nil | String | Int64 | Float64 | Bool | Hash(String, JSON::Type) | Array(JSON::Type)

    # clear the params.
    def clear_params
      @params = HTTP::Params.new({} of String => Array(String))
    end

    def parse_params
      parse_part(request.query)
      if content_type = request.headers["Content-Type"]?
        parse_multipart if content_type.try(&.starts_with?(MULTIPART_FORM))
        parse_part(request.body) if content_type.try(&.starts_with?(URL_ENCODED_FORM))
        parse_json if content_type == APPLICATION_JSON
      end
    end

    def upgrade_request_method!
      if params[METHOD]?
        method = params[METHOD]
        request.method = method.upcase if OVERRIDE_METHODS.includes?(method)
      end
    end

    def merge_route_params
      route_params.each { |k, v| params.add(k.to_s, v) }
    end

    def route_params
      route.params
    end

    def parse_json
      if body = request.body.not_nil!.gets_to_end
        if body.size > 2
          case json = JSON.parse(body).raw
          when Hash
            json.each do |key, value|
              params[key.as(String)] = value.to_s
            end
          when Array
            params["_json"] = json.to_s
          end
        end
      end
    end

    def parse_multipart
      HTTP::FormData.parse(request) do |upload|
        next unless upload
        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          files[upload.name] = Files::File.new(upload: upload)
        else
          params.add(upload.name, upload.body.gets_to_end)
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
        params.add(key, value)
      end
    end
  end
end
