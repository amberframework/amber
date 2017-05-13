module Amber
  class Route
    property :handler, :action, :verb, :resource, :valve, :params, :scope

    def initialize(@verb : String,
                   @resource : String,
                   @handler : Proc(HTTP::Server::Context, Symbol, String),
                   @action : Symbol = :index,
                   @valve : Symbol = :web,
                   @scope : String = "")
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
