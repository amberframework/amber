require "../../spec_helper"

class EnforcedCreateSchema < Amber::Schema::Definition
  content_type "application/json", "application/cbor", "application/cose"
  additional_properties false
  field :email, String, required: true, format: "email"
  field :age, Int32, required: true, min: 18
  field :newsletter, Bool, default: false
  field :request_id, String, required: true, source: Amber::Schema::ParamSource::Header, source_name: "X-Request-ID"
  field :preview, Bool, default: false, source: Amber::Schema::ParamSource::Query
  field :locale, String, default: "en", source: Amber::Schema::ParamSource::Cookie
end

class EnforcedResponseSchema < Amber::Schema::Definition
  content_type "application/json", "application/cbor", "application/cose"
  field :email, String, required: true
  field :age, Int32, required: true
end

class JSONOnlyResponseSchema < Amber::Schema::Definition
  field :name, String, required: true
end

class JSONOnlyResponseController < Amber::Controller::Base
  response_schema :show, JSONOnlyResponseSchema

  def show
    respond_with({"name" => JSON::Any.new("Amber")})
  end
end

class EnforcedSchemaController < Amber::Controller::Base
  schema :create, EnforcedCreateSchema
  response_schema :create, EnforcedResponseSchema

  class_property action_calls = 0

  def create
    self.class.action_calls += 1
    input = validated_as(EnforcedCreateSchema)
    respond_with({
      "email" => JSON::Any.new(input.email.not_nil!),
      "age"   => JSON::Any.new(input.age.not_nil!),
    })
  end
end

class InlineSchemaController < Amber::Controller::Base
  schema :create do
    field :name, String, required: true
  end

  def create
    respond_with({"name" => validated_params.not_nil!["name"]})
  end
end

private def schema_context(body : String | Bytes, content_type = "application/json", accept = "application/json", path = "/users")
  request = HTTP::Request.new("POST", path, HTTP::Headers{
    "Content-Type" => content_type,
    "Accept"       => accept,
    "X-Request-ID" => "req-1",
    "Cookie"       => "locale=fr",
  }, body.is_a?(String) ? IO::Memory.new(body) : IO::Memory.new(body))
  output = IO::Memory.new
  response = HTTP::Server::Response.new(output)
  {HTTP::Server::Context.new(request, response), output}
end

private def response_body(output : IO::Memory) : Bytes
  bytes = output.to_slice
  separator_index = nil.as(Int32?)
  (0..bytes.size - 4).each do |index|
    if bytes[index] == 13_u8 && bytes[index + 1] == 10_u8 && bytes[index + 2] == 13_u8 && bytes[index + 3] == 10_u8
      separator_index = index
      break
    end
  end
  index = separator_index || raise "HTTP response did not contain a header separator"
  bytes[index + 4, bytes.size - index - 4]
end

describe "enforced controller schemas" do
  before_each do
    EnforcedSchemaController.action_calls = 0
  end

  it "automatically rejects invalid JSON before the action" do
    context, output = schema_context(%({"email":"not-an-email","age":17}))
    controller = EnforcedSchemaController.new(context)

    controller.run_before_filter(:create)

    context.response.status_code.should eq(422)
    context.content.should_not be_nil
    EnforcedSchemaController.action_calls.should eq(0)
    context.response.close
    output.to_s.should contain("invalid_format")
    output.to_s.should contain("out_of_range")
  end

  it "coerces once and exposes typed schema getters to a successful action" do
    context, _output = schema_context(%({"email":"amber@example.com","age":"21"}))
    controller = EnforcedSchemaController.new(context)

    controller.run_before_filter(:create)
    context.content.should be_nil
    controller.validated_params.not_nil!["age"].as_i.should eq(21)
    controller.validated_as(EnforcedCreateSchema).newsletter.should be_false
    controller.validated_as(EnforcedCreateSchema).locale.should eq("fr")

    controller.create
    EnforcedSchemaController.action_calls.should eq(1)
    context.response.status_code.should eq(200)
  end

  it "binds query parameters through the same typed contract" do
    context, _output = schema_context(%({"email":"amber@example.com","age":21}), path: "/users?preview=true")
    controller = EnforcedSchemaController.new(context)

    controller.run_before_filter(:create)
    controller.validated_as(EnforcedCreateSchema).preview.should be_true
  end

  it "validates the same contract from CBOR" do
    body = Amber::Schema::CBOR.encode({
      "email" => JSON::Any.new("amber@example.com"),
      "age"   => JSON::Any.new(21_i64),
    })
    context, _output = schema_context(body, "application/cbor")
    controller = EnforcedSchemaController.new(context)

    controller.run_before_filter(:create)
    context.content.should be_nil
    controller.validated_as(EnforcedCreateSchema).age.should eq(21)
  end

  it "decrypts, decodes, and validates inbound COSE" do
    provider = Amber::Schema::COSE::KeyProvider.new(Bytes.new(32, 7_u8), "test")
    Amber::Schema::COSE.configure(provider)
    cbor = Amber::Schema::CBOR.encode({
      "email" => JSON::Any.new("amber@example.com"),
      "age"   => JSON::Any.new(21_i64),
    })
    context, _output = schema_context(Amber::Schema::COSE.encrypt0(cbor, provider), "application/cose")
    controller = EnforcedSchemaController.new(context)

    controller.run_before_filter(:create)
    context.content.should be_nil
    controller.validated_as(EnforcedCreateSchema).email.should eq("amber@example.com")
  end

  it "negotiates and validates a CBOR response" do
    context, output = schema_context(%({"email":"amber@example.com","age":21}), accept: "application/cbor")
    controller = EnforcedSchemaController.new(context)
    controller.run_before_filter(:create)
    controller.create

    context.response.content_type.should eq("application/cbor")
    decoded = Amber::Schema::CBOR.decode_object(IO::Memory.new(response_body(output)))
    decoded["email"].as_s.should eq("amber@example.com")
    decoded["age"].as_i.should eq(21)
  end

  it "negotiates an authenticated COSE response that opens to the declared CBOR schema" do
    provider = Amber::Schema::COSE::KeyProvider.new(Bytes.new(32, 11_u8), "response-key")
    Amber::Schema::COSE.configure(provider)
    context, output = schema_context(%({"email":"amber@example.com","age":21}), accept: "application/cose")
    controller = EnforcedSchemaController.new(context)
    controller.run_before_filter(:create)
    controller.create

    context.response.content_type.should eq("application/cose")
    context.response.headers["X-Amber-Wire-Format"].should contain("chacha20-poly1305")
    plaintext = Amber::Schema::COSE.decrypt0(IO::Memory.new(response_body(output)), provider)
    decoded = Amber::Schema::CBOR.decode_object(IO::Memory.new(plaintext))
    decoded["email"].as_s.should eq("amber@example.com")
  end

  it "stops malformed request bodies with HTTP 400" do
    context, output = schema_context(%({"email":), "application/json")
    EnforcedSchemaController.new(context).run_before_filter(:create)

    context.response.status_code.should eq(400)
    context.content.should_not be_nil
    context.response.close
    output.to_s.should contain("invalid_request_body")
  end

  it "rejects undeclared media types with HTTP 415" do
    context, _output = schema_context("name=Amber", "application/x-www-form-urlencoded")
    EnforcedSchemaController.new(context).run_before_filter(:create)

    context.response.status_code.should eq(415)
    context.content.should_not be_nil
  end

  it "rejects undeclared body fields when the contract is closed" do
    context, output = schema_context(%({"email":"amber@example.com","age":21,"admin":true}))
    EnforcedSchemaController.new(context).run_before_filter(:create)

    context.response.status_code.should eq(422)
    context.response.close
    output.to_s.should contain("unexpected_field")
    output.to_s.should contain("admin")
  end

  it "returns HTTP 500 instead of emitting a response outside its contract" do
    context, output = schema_context(%({"email":"amber@example.com","age":21}))
    controller = EnforcedSchemaController.new(context)
    controller.run_before_filter(:create)

    controller.respond_with({"email" => JSON::Any.new("amber@example.com")})
    context.response.status_code.should eq(500)
    context.response.close
    output.to_s.should contain("response_schema_mismatch")
  end

  it "enforces the status code declared by the response contract" do
    context, output = schema_context(%({"email":"amber@example.com","age":21}))
    controller = EnforcedSchemaController.new(context)
    controller.run_before_filter(:create)

    controller.respond_with({
      "email" => JSON::Any.new("amber@example.com"),
      "age"   => JSON::Any.new(21_i64),
    }, status: 201)
    context.response.status_code.should eq(500)
    context.response.close
    output.to_s.should contain("response_schema_mismatch")
  end

  it "returns HTTP 406 instead of emitting a media type outside the response contract" do
    context, output = schema_context(%({}), accept: "application/cbor")
    controller = JSONOnlyResponseController.new(context)
    controller.run_before_filter(:show)
    controller.show

    context.response.status_code.should eq(406)
    context.response.close
    output.to_s.should contain("response_media_type_not_acceptable")
  end

  it "compiles and enforces action-local inline schemas" do
    context, output = schema_context(%({}))
    InlineSchemaController.new(context).run_before_filter(:create)

    context.response.status_code.should eq(422)
    context.response.close
    output.to_s.should contain("required_field_missing")
  end
end
