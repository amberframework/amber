require "../../spec_helper"

class NamedTupleSubscriberResponseSchema < Amber::Schema::Definition
  field :id, Int64, required: true
  field :email_address, String, required: true
end

class NamedTupleSubscriberController < Amber::Controller::Base
  response_schema :create, NamedTupleSubscriberResponseSchema

  def create
    respond_with({id: 7_i64, email_address: "amber@example.com"}, status: 201)
  end
end

class NamedTupleOpenController < Amber::Controller::Base
  def show
    respond_with({
      count:        3,
      ratio:        0.5,
      is_published: true,
      summary:      nil,
      list_of_tags: ["crystal", "amber"],
      author:       {first_name: "Ada"},
      raw:          JSON::Any.new("kept"),
    })
  end
end

private def named_tuple_context : {HTTP::Server::Context, IO::Memory}
  request = HTTP::Request.new("POST", "/subscribers", HTTP::Headers{
    "Content-Type" => "application/json",
    "Accept"       => "application/json",
  }, IO::Memory.new("{}"))
  output = IO::Memory.new
  response = HTTP::Server::Response.new(output)
  {HTTP::Server::Context.new(request, response), output}
end

private def json_body(output : IO::Memory) : String
  text = output.to_s
  separator = text.index("\r\n\r\n") || raise "HTTP response did not contain a header separator"
  text[(separator + 4)..]
end

describe Amber::Schema::ControllerIntegration do
  describe "#respond_with" do
    context "with a NamedTuple" do
      it "answers with string keys that satisfy the declared response schema" do
        context, output = named_tuple_context
        NamedTupleSubscriberController.new(context).create

        context.response.status_code.should eq(201)
        context.response.close
        body = JSON.parse(json_body(output))
        body["id"].as_i64.should eq(7_i64)
        body["email_address"].as_s.should eq("amber@example.com")
      end

      it "converts Int32, Float, Bool, nil, array, nested NamedTuple and JSON::Any values" do
        context, output = named_tuple_context
        NamedTupleOpenController.new(context).show

        context.response.status_code.should eq(200)
        context.response.close
        body = JSON.parse(json_body(output))
        body["count"].as_i64.should eq(3_i64)
        body["ratio"].as_f.should eq(0.5)
        body["is_published"].as_bool.should be_true
        body["summary"].raw.should be_nil
        body["list_of_tags"].as_a.map(&.as_s).should eq(["crystal", "amber"])
        body["author"]["first_name"].as_s.should eq("Ada")
        body["raw"].as_s.should eq("kept")
      end
    end
  end
end
