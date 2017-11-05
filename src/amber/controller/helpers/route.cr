module Amber::Controller::Helpers
  module Route
    def route_action
      context.request_handler.action
    end

    def route_resource
      context.request_handler.resource
    end

    def route_scope
      context.request_handler.scope
    end

    def route_controller
      context.request_handler.controller
    end

    def controller_name
      self.class.name.gsub(/Controller/i, "")
    end
  end
end
