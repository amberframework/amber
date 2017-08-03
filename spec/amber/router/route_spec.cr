require "../../../spec_helper"

module Amber
  module Router
    describe Route do
      describe "#call" do
        it "performs request lifecycle" do
          method = "GET"
          action = :show
          request = HTTP::Request.new(method, "/#{action}")
          context = create_context(request)
          route = Route.new("GET",
            "/#{action}",
            build_handler(action, context),
            action,
            :web,
            "",
            "FakeController")

          result = route.call(context)

          context.response.status_code.should eq 200
        end

        it "halts request lifecycle" do
          method = "GET"
          action = :halt_request
          request = HTTP::Request.new(method, "/#{action}")
          context = create_context(request)
          route = Route.new("GET",
            "/#{action}",
            build_handler(action, context),
            action,
            :web,
            "",
            "FakeController")

          result = route.call(context)

          context.response.status_code.should eq 800
        end
      end
    end
  end
end

class FakeController < Amber::Controller::Base
  before_action do
    only :halt_request { halt_lifecycle }
  end

  def show
    "Action show result"
  end

  def halt_lifecycle
    halt(status_code = 800)
  end

  def halt_request
    "Should not be in request"
  end
end

def build_handler(action, context)
  handler = ->(context : HTTP::Server::Context, action : Symbol) {
    controller = FakeController.new(context)
    controller.run_before_filter(:all)
    controller.run_before_filter(action)
    content = controller.show
    puts context.response.status_code
    controller.run_after_filter(action)
    controller.run_after_filter(:all)
    context.response.print content
    context.response.close
  }
end

def build_halt_handler(action, context)
  handler = ->(context : HTTP::Server::Context, action : Symbol) {
    controller = FakeController.new(context)
    controller.run_before_filter(:all)
    controller.run_before_filter(action)
    content = controller.halt_request
    puts context.response.status_code
    controller.run_after_filter(action)
    controller.run_after_filter(:all)
    context.response.print content
    context.response.close
  }
end

