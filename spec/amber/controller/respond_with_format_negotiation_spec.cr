require "../../spec_helper"

class NegotiationJSONOnlyResponseSchema < Amber::Schema::Definition
  field :title, String, required: true
end

class NegotiationJSONOnlyController < Amber::Controller::Base
  response_schema :show, NegotiationJSONOnlyResponseSchema

  def show
    respond_with({title: "latest"})
  end
end

class NegotiationOpenController < Amber::Controller::Base
  def show
    respond_with({title: "latest"})
  end
end

private def negotiated_content_type(controller_class, accept : String?) : {Int32, String?}
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  headers["Accept"] = accept if accept
  request = HTTP::Request.new("GET", "/notes/latest", headers)
  response = HTTP::Server::Response.new(IO::Memory.new)
  context = HTTP::Server::Context.new(request, response)
  controller = controller_class.new(context)
  controller.run_before_filter(:show)
  controller.show
  {response.status_code, response.headers["Content-Type"]?}
end

describe Amber::Schema::ControllerIntegration do
  describe "#respond_with format negotiation" do
    context "on an endpoint without a response schema" do
      it "answers JSON when the client refuses CBOR with q=0" do
        negotiated_content_type(NegotiationOpenController, "application/cbor;q=0, application/json")
          .should eq({200, "application/json"})
      end

      it "answers the format with the higher quality" do
        negotiated_content_type(NegotiationOpenController, "application/cbor;q=0.4, application/json;q=0.9")
          .should eq({200, "application/json"})
        negotiated_content_type(NegotiationOpenController, "application/json;q=0.4, application/cbor")
          .should eq({200, "application/cbor"})
      end

      it "keeps preferring CBOR over JSON when the client names both with equal quality" do
        negotiated_content_type(NegotiationOpenController, "application/json, application/cbor")
          .should eq({200, "application/cbor"})
      end

      it "answers JSON for a wildcard, a missing header, or an unrelated type" do
        negotiated_content_type(NegotiationOpenController, "*/*").should eq({200, "application/json"})
        negotiated_content_type(NegotiationOpenController, "application/*").should eq({200, "application/json"})
        negotiated_content_type(NegotiationOpenController, nil).should eq({200, "application/json"})
        negotiated_content_type(NegotiationOpenController, "text/html").should eq({200, "application/json"})
      end

      it "lets an exact q=0 override a wildcard" do
        negotiated_content_type(NegotiationOpenController, "application/cbor;q=0, */*")
          .should eq({200, "application/json"})
      end
    end

    context "on an endpoint whose response schema offers only JSON" do
      it "answers JSON when the client prefers CBOR but also accepts JSON" do
        negotiated_content_type(NegotiationJSONOnlyController, "application/cbor, application/json;q=0.5")
          .should eq({200, "application/json"})
      end

      it "answers 406 when the client accepts only CBOR" do
        negotiated_content_type(NegotiationJSONOnlyController, "application/cbor")
          .should eq({406, "application/json"})
      end
    end
  end
end
