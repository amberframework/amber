module Parser
  class Route
    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX

    def initialize(@params : Amber::Router::Params, @request : HTTP::Request)
    end

    def parse
      route_params_without_ext.each do |k, v|
        @params[k] = v
      end
    end

    private def route_params_without_ext
      unless route_params.empty?
        key = route_params.keys.last
        route_params[key] = route_params[key].sub(TYPE_EXT_REGEX, "")
      end
      route_params
    end

    private def route_params
      @request.route_params
    end
  end
end