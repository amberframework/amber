module Amber::Controller::Helpers
  module Route
    def action_name
      request.route.action
    end

    def route_resource
      request.route.resource
    end

    def route_scope
      request.route.scope
    end

    def controller_name
      self.class.name.sub(/Controller$/, "").underscore
    end
  end
end
