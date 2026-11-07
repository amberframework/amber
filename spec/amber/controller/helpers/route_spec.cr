require "../../../spec_helper"

class ReportControllerController < Amber::Controller::Base
end

class ControllerWidgets < Amber::Controller::Base
end

private def controller_for(controller_class)
  controller_class.new(create_context(HTTP::Request.new("GET", "/")))
end

describe Amber::Controller::Helpers::Route do
  describe "#controller_name" do
    it "drops a trailing Controller and underscores the rest" do
      controller_for(HelloController).controller_name.should eq "hello"
      controller_for(ReportControllerController).controller_name.should eq "report_controller"
    end

    it "keeps a name that does not end in Controller" do
      controller_for(ControllerWidgets).controller_name.should eq "controller_widgets"
    end
  end
end
