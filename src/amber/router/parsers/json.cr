module Amber::Router::Parsers
  module JSON
    def self.parse(request : HTTP::Request)
      json_params = Types::Params.new
      if body = request.body.not_nil!.gets_to_end
        if body.size > 2
          case json = ::JSON.parse_raw(body)
          when Hash
            json.each do |key, value|
              if value.is_a?(String)
                json_params[key.as(String)] = value
              else
                json_params[key.as(String)] = value.to_json
              end
            end
          when Array
            json_params["_json"] = json.to_json
          end
        end
      end
      json_params
    end
  end
end
