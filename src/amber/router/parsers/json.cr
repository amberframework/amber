module Amber::Router::Parsers
  module JSON
    def self.parse(request : HTTP::Request)
      json_params = Types::Params.new

      return json_params unless request_body = request.body
      return json_params unless body = request_body.gets_to_end
      return json_params unless body.size > 2
      return json_params unless parsed = ::JSON.parse body

      json_params["_json"] = body

      if parsed.as_h?
        parsed.as_h.each do |key, value|
          if value.as_s?
            json_params[key.to_s] = value.as_s
          else
            json_params[key.to_s] = value.to_json
          end
        end
      end

      json_params
    end
  end
end
