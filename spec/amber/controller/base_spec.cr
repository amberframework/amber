require "../../spec_helper"

module Amber::Controller
  describe Base do
    controller = build_controller

    it "responds to context methods" do
      controller.responds_to?(:redirect_to).should eq true
      controller.responds_to?(:cookies).should eq true
      controller.responds_to?(:format).should eq true
      controller.responds_to?(:port).should eq true
      controller.responds_to?(:requested_url).should eq true
      controller.responds_to?(:session).should eq true
      controller.responds_to?(:valve).should eq true
      controller.responds_to?(:route).should eq true
      controller.responds_to?(:websocket?).should eq true
      controller.responds_to?(:get?).should eq true
      controller.responds_to?(:post?).should eq true
      controller.responds_to?(:patch?).should eq true
      controller.responds_to?(:put?).should eq true
      controller.responds_to?(:delete?).should eq true
      controller.responds_to?(:head?).should eq true
      controller.responds_to?(:client_ip).should eq true
      controller.responds_to?(:request).should eq true
      controller.responds_to?(:response).should eq true
      controller.responds_to?(:action_name).should eq true
      controller.responds_to?(:route_resource).should eq true
      controller.responds_to?(:route_scope).should eq true
      controller.responds_to?(:controller_name).should eq true
      controller.responds_to?(:redirect_back).should eq true
    end

    describe "#session" do
      controller = build_controller
      controller.session["name"] = "David"

      it "sets a session value" do
        controller.session["name"].should eq "David"
      end

      it "has a session id" do
        controller.session.id.not_nil!.size.should eq 36
      end
    end
  end
end
