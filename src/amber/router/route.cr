module Amber
  class Route
    property :controller, :handler, :action, :verb, :resource, :valve, :params,:scope

    def initialize(@verb : String,
                   @resource : String,
                   @controller = Controller::Base.new,
                   @handler : Proc(String) = ->{ "500" },
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
      controller.set_context(context)
      controller.run_before_filter(:all)
      controller.run_before_filter(action)
      content = handler.call
      controller.run_after_filter(action)
      controller.run_after_filter(:all)
      content
    end
  end
end
