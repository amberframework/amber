module Parser
  class JSON
    def initialize(@params : Amber::Router::Params, @request : HTTP::Request)
    end

    def parse
      if body = @request.body.not_nil!.gets_to_end
        if body.size > 2
          case json = ::JSON.parse_raw(body)
          when Hash
            json.each do |key, value|
              if value.is_a?(String)
                @params[key.as(String)] = value
              else
                @params[key.as(String)] = value.to_json
              end
            end
          when Array
            @params["_json"] = json.to_json
          end
        end
      end
    end
  end
end