require "../../spec_helper"

class TypedHashSubscriberResponseSchema < Amber::Schema::Definition
  field :id, Int64, required: true
  field :email_address, String, required: true
end

class TypedHashSubscriberController < Amber::Controller::Base
  response_schema :create, TypedHashSubscriberResponseSchema, status: 201

  def create
    respond_with({:id => 7, :email_address => "amber@example.com"}, status: 201)
  end
end

class TypedHashOpenController < Amber::Controller::Base
  def show_strings
    respond_with({"title" => "latest", "summary" => "kept"})
  end

  def show_counts
    respond_with({"count" => 3, "total" => 10})
  end

  def show_tags
    respond_with({"list_of_tags" => ["crystal", "amber"]})
  end

  def show_nothing
    respond_with
  end
end

private def typed_hash_context(accept = "application/json") : {HTTP::Server::Context, IO::Memory}
  request = HTTP::Request.new("POST", "/subscribers", HTTP::Headers{
    "Content-Type" => "application/json",
    "Accept"       => accept,
  }, IO::Memory.new("{}"))
  output = IO::Memory.new
  response = HTTP::Server::Response.new(output)
  {HTTP::Server::Context.new(request, response), output}
end

private def typed_hash_body(output : IO::Memory) : String
  text = output.to_s
  separator = text.index("\r\n\r\n") || raise "HTTP response did not contain a header separator"
  text[(separator + 4)..]
end

private def typed_hash_body_bytes(output : IO::Memory) : Bytes
  text = output.to_s
  separator = text.byte_index("\r\n\r\n") || raise "HTTP response did not contain a header separator"
  output.to_slice[(separator + 4)..]
end

describe Amber::Schema::ControllerIntegration do
  describe "#respond_with" do
    context "with a typed Hash" do
      it "answers a Hash(Symbol, Int32 | String) with string keys that satisfy the declared response schema" do
        context, output = typed_hash_context
        controller = TypedHashSubscriberController.new(context)
        controller.run_before_filter(:create)
        controller.create

        context.response.status_code.should eq(201)
        context.response.close
        body = JSON.parse(typed_hash_body(output))
        body["id"].as_i64.should eq(7_i64)
        body["email_address"].as_s.should eq("amber@example.com")
      end

      it "answers a Hash(String, String)" do
        context, output = typed_hash_context
        controller = TypedHashOpenController.new(context)
        controller.run_before_filter(:show_strings)
        controller.show_strings

        context.response.status_code.should eq(200)
        context.response.close
        typed_hash_body(output).should eq(%({"title":"latest","summary":"kept"}))
      end

      it "answers a Hash(String, Int32)" do
        context, output = typed_hash_context
        controller = TypedHashOpenController.new(context)
        controller.run_before_filter(:show_counts)
        controller.show_counts

        context.response.close
        typed_hash_body(output).should eq(%({"count":3,"total":10}))
      end

      it "answers a Hash(String, Array(String)) as CBOR when the client asks for CBOR" do
        context, output = typed_hash_context(accept: "application/cbor")
        controller = TypedHashOpenController.new(context)
        controller.run_before_filter(:show_tags)
        controller.show_tags

        context.response.content_type.should eq("application/cbor")
        context.response.close
        decoded = Amber::Schema::CBOR.decode_object(IO::Memory.new(typed_hash_body_bytes(output)))
        decoded["list_of_tags"].as_a.map(&.as_s).should eq(["crystal", "amber"])
      end

      it "answers an empty object when given no data" do
        context, output = typed_hash_context
        controller = TypedHashOpenController.new(context)
        controller.run_before_filter(:show_nothing)
        controller.show_nothing

        context.response.close
        typed_hash_body(output).should eq("{}")
      end
    end
  end
end
