module Amber::Controller::Helpers
  module Route
    def action_name
      context.request_handler.action
    end

    def route_resource
      context.request_handler.resource
    end

    def route_scope
      context.request_handler.scope
    end

    def controller_name
      self.class.name.sub(/Controller$/, "").underscore
    end
  end
end
