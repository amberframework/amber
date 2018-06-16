module Amber::Router::Parsers
  module JSON
    def self.parse(request : HTTP::Request)
      json_params = Types::Params.new
      # if request_body = request.body
      #   if body = request_body.gets_to_end
      #     if body.size > 2
      #       case json = ::JSON.parse(body)
      #       when .as_h?
      #         json.as_h.each do |key, value|
      #           if value.is_a?(String)
      #             json_params[key.as(String)] = value
      #           else
      #             json_params[key.as(String)] = value.to_json
      #           end
      #         end
      #       when .as_a?
      #         json_params["_json"] = json
      #           case value
      #           when .as_i?
      #             value.as_i
      #           when .as_s?
      #             value.as_s
      #           else
      #             raise "cannot convert incoming json value"
      #           end
      #         end
      #       end
      #     end
      #   end
      # end
      json_params
    end
  end
end
