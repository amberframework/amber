module Amber
  class Route
    property :handler, :action, :verb, :resource, :valve, :params, :scope, :controller

    def initialize(@verb : String,
                   @resource : String,
                   @handler : Proc(HTTP::Server::Context, Symbol, String),
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

    def trail_head
      "head#{scope}#{resource}"
    end

    def call(context)
      handler.call(context, action)
    end
  end
end
