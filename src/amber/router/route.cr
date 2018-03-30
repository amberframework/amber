module Amber
  struct Route
    property :handler, :action, :verb, :resource, :valve, :params, :scope, :controller

    def initialize(@verb : String,
                   @resource : String,
                   @handler : HTTP::Server::Context ->,
                   @action : Symbol = :index,
                   @valve : Symbol = :web,
                   @scope : String = "",
                   @controller : String = "")
    end

    def to_json
      JSON.build do |json|
        json.object do
          json.field "verb", verb
          json.field "controller", controller
          json.field "action", action.to_s
          json.field "valve", valve.to_s
          json.field "scope", scope
          json.field "resource", resource
        end
      end
    end

    def trail
      "#{verb.to_s.downcase}#{scope}#{resource}"
    end

    def call(context)
      handler.call(context)
    end

    def substitute_keys_in_path(params : Hash(String, String)? = nil)
      result = scope.to_s + resource.dup
      if !params.nil?
        params.each do |k, v|
          if result.includes?(":#{k}")
            result = result.gsub(":#{k}", v)
            params.delete(k)
          end
        end
      end
      {result, params}
    end
  end
end
