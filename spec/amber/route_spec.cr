require "./../spec_helper"

module Amber
  describe Route do
    it "Initializes correctly with Decendant controller" do
      handler = ->(context : HTTP::Server::Context, action : Symbol) {
        "Hey yo world!"
      }
      request = HTTP::Request.new("GET", "/?test=test")
      context = create_context(request)

      route = Route.new("GET", "/", handler)

      route.class.should eq Route
    end

    describe "#call" do
      context "before action" do
        it "does not execute action" do
          handler = ->(context : HTTP::Server::Context, action : Symbol) {
            controller = FakeController.new(context)
            controller.run_before_filter(action) unless context.content
            content = controller.halt_action unless context.content
            controller.run_after_filter(action) unless context.content
            content.to_s
          }

          request = HTTP::Request.new("GET", "")
          context = create_context(request)
          route = Route.new("GET", "", handler, :halt_action)

          route.call(context).should eq ""
          context.response.status_code.should eq 900
          context.content.should eq ""
        end
      end

      context "when redirecting" do
        it "halts request execution" do
          new_handler = ->(context : HTTP::Server::Context, action : Symbol) {
            controller = FakeRedirectController.new(context)
            controller.run_before_filter(action) unless context.content
            content = controller.redirect_action unless context.content
            controller.run_after_filter(action) unless context.content
            content.to_s
          }

          request = HTTP::Request.new("GET", "/")
          context = create_context(request)
          route = Route.new("GET", "", new_handler, :redirect_action)

          route.call(context).should eq ""
          context.response.status_code.should eq 302
          context.content.should eq "Redirecting to /"
        end
      end
    end
  end
end

class FakeController < Amber::Controller::Base
  before_action do
    only :halt_action { halt!(900) }
  end

  def halt_action
    raise "Should not reach this action"
    ""
  end
end

class FakeRedirectController < Amber::Controller::Base
  def redirect_action
    redirect_to "/"
    ""
  end
end
