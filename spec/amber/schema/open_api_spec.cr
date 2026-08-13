require "../../spec_helper"

class OpenAPIAddressSchema < Amber::Schema::Definition
  field :city, String, required: true
end

class OpenAPICreateSchema < Amber::Schema::Definition
  content_type "application/json", "application/cbor", "application/cose"
  additional_properties false
  field :name, String, required: true, min_length: 2, description: "Display name"
  field :age, Int32, min: 18
  field :trace_id, String, required: true, source: Amber::Schema::ParamSource::Header, source_name: "X-Trace-ID"
  field :preview, Bool, default: false, source: Amber::Schema::ParamSource::Query
  field :account_id, Int64, required: true, source: Amber::Schema::ParamSource::Path
  field :latitude, Float64
  field :longitude, Float64
  requires_together :latitude, :longitude
  field :email, String
  field :phone, String
  requires_one_of :email, :phone
  field :kind, String, enum: ["person", "business"]
  when_field :kind, "business" do
    field :company_name, String, required: true
  end
  nested :address, OpenAPIAddressSchema, required: true
end

class OpenAPIResponseSchema < Amber::Schema::Definition
  content_type "application/json", "application/cbor", "application/cose"
  field :id, Int64, required: true
  field :name, String, required: true
end

class OpenAPISchemaController < Amber::Controller::Base
  schema :create, OpenAPICreateSchema
  response_schema :create, OpenAPIResponseSchema, status: 201, description: "User created"
end

describe Amber::Schema::OpenAPI do
  it "generates request, response, parameter, binary media, and validation documentation from one contract" do
    Amber::Schema::RouteRegistry.clear
    Amber::Schema::RouteRegistry.add_route({
      controller: "OpenAPISchemaController",
      action:     "create",
      verb:       "POST",
      path:       "/users/:account_id",
    })

    document = JSON.parse(Amber::Schema::OpenAPI.generate(
      title: "Amber API",
      version: "2.0.0",
      server_url: "https://example.test"
    ))

    document["openapi"].as_s.should eq("3.1.0")
    operation = document["paths"]["/users/{account_id}"]["post"]
    operation["requestBody"]["content"]["application/json"]["schema"]["$ref"].as_s.should contain("OpenAPICreateSchemaRequestBody")
    operation["requestBody"]["content"]["application/cbor"]["schema"]["$ref"].as_s.should contain("OpenAPICreateSchemaRequestBody")
    operation["requestBody"]["content"]["application/cose"]["schema"]["format"].as_s.should eq("binary")
    operation["responses"]["201"]["description"].as_s.should eq("User created")
    operation["responses"]["415"]["description"].as_s.should contain("media type")
    operation["responses"]["422"]["description"].as_s.should contain("validation")
    operation["responses"]["500"]["description"].as_s.should contain("response schema")

    parameters = operation["parameters"].as_a
    parameters.any? { |parameter| parameter["name"].as_s == "X-Trace-ID" && parameter["in"].as_s == "header" }.should be_true
    parameters.any? { |parameter| parameter["name"].as_s == "preview" && parameter["in"].as_s == "query" }.should be_true
    parameters.any? { |parameter| parameter["name"].as_s == "account_id" && parameter["in"].as_s == "path" }.should be_true

    component = document["components"]["schemas"]["OpenAPICreateSchemaRequestBody"]
    component["required"].as_a.map(&.as_s).should contain("name")
    component["properties"]["name"]["minLength"].as_i.should eq(2)
    component["properties"]["name"]["description"].as_s.should eq("Display name")
    component["properties"].as_h.has_key?("trace_id").should be_false
    component["properties"].as_h.has_key?("account_id").should be_false
    component["additionalProperties"].as_bool.should be_false
    component["properties"]["address"]["$ref"].as_s.should contain("OpenAPIAddressSchema")
    document["components"]["schemas"]["OpenAPIAddressSchema"]["required"].as_a.map(&.as_s).should contain("city")
    component["dependentRequired"]["latitude"].as_a.map(&.as_s).should contain("longitude")
    relationships = component["allOf"].to_json
    relationships.should contain("oneOf")
    relationships.should contain("if")
    relationships.should contain("then")
    relationships.should contain("company_name")
  ensure
    Amber::Schema::RouteRegistry.clear
  end
end
