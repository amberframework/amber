module Parser
  module JSON
    def self.parse(params : HTTP::Params, request : HTTP::Request)
      if body = request.body.not_nil!.gets_to_end
        if body.size > 2
          case json = ::JSON.parse_raw(body)
          when Hash
            json.each do |key, value|
              if value.is_a?(String)
                params.add(key.as(String), value)
              else
                params.add(key.as(String), value.to_json)
              end
            end
          when Array
            params.add("_json", json.to_json)
          end
        end
      end
    end
  end
end
