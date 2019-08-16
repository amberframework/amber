require "./scope"

module Amber
  struct Route
    property :handler, :action, :verb, :resource, :valve, :params, :scope, :controller, :constraints

    def initialize(@verb : String,
                   @resource : String,
                   @handler : HTTP::Server::Context ->,
                   @action : Symbol = :index,
                   @valve : Symbol = :web,
                   @scope : Router::Scope = Router::Scope.new,
                   @controller : String = "",
                   @constraints : Hash = {} of String => Regex)
    end

    def to_json
      JSON.build do |json|
        json.object do
          json.field "verb", verb
          json.field "controller", controller
          json.field "action", action.to_s
          json.field "valve", valve.to_s
          json.field "scope", scope.to_s
          json.field "resource", resource
          json.field "constraints" do
            json.object do
              constraints.each do |key, value|
                json.field key, value.to_s
              end
            end
          end
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
