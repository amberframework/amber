require "spec"
require "../../src/amber"
require "../../src/amber/testing/testing"

class APICardReturnTypeController < Amber::Controller::Base
  def public_legacy_params : Amber::Validators::Params
    legacy_params
  end

  def public_params : Amber::Controller::SchemaParamsWrapper | Amber::Validators::Params
    params
  end

  def public_raw_params : Amber::Router::Params
    raw_params
  end
end

class APICardReturnTypeRequestHelpers
  include Amber::Testing::RequestHelpers

  def test_get : Amber::Testing::TestResponse
    get("/type-probe")
  end
end

describe "Amber public API return types" do
  it "declares controller parameter and request-helper returns" do
    context = Amber::Testing::ContextBuilder.new.query_param("name", "Ada").build
    controller = APICardReturnTypeController.new(context)
    typeof(controller.public_legacy_params).should eq(Amber::Validators::Params)
    typeof(controller.public_params).should eq(Amber::Controller::SchemaParamsWrapper | Amber::Validators::Params)
    typeof(controller.public_raw_params).should eq(Amber::Router::Params)
    typeof(APICardReturnTypeRequestHelpers.new.test_get).should eq(Amber::Testing::TestResponse)
  end

  it "declares validator and schema-wrapper return types" do
    context = Amber::Testing::ContextBuilder.new.query_param("name", "Ada").build
    params = Amber::Validators::Params.new(context.params)
    params.validation do
      required(:name) { |value| value.size > 1 }
    end
    typeof(params.validation { required(:name) }).should eq(Amber::Validators::Params)
    typeof(params.valid?).should eq(Bool)
    typeof(params.validate!).should eq(Hash(String, String?))
    typeof(params.add_rule(Amber::Validators::BaseRule.new(:name, nil))).should eq(Array(Amber::Validators::BaseRule))
    typeof(params.to_h).should eq(Hash(String, String?))
    typeof(params.to_unsafe_h).should eq(Hash(String, String))

    builder = Amber::Validators::ValidationBuilder.new(params)
    typeof(builder.required(:name)).should eq(Array(Amber::Validators::BaseRule))
    typeof(builder.required(:nickname, "required", true) { |value| !value.empty? }).should eq(Array(Amber::Validators::BaseRule))
    typeof(builder.optional(:nickname)).should eq(Array(Amber::Validators::BaseRule))
    typeof(builder.optional(:nickname) { |value| !value.empty? }).should eq(Array(Amber::Validators::BaseRule))

    wrapper = Amber::Controller::SchemaParamsWrapper.new(
      {} of String => JSON::Any,
      context.params
    )
    typeof(wrapper["name"]).should eq(String)
    typeof(wrapper["missing"]?).should eq(String?)
    typeof(wrapper.validation { required(:name) }).should eq(Amber::Validators::Params)
    typeof(wrapper.to_h).should eq(Hash(String, String?))
    typeof(wrapper.to_unsafe_h).should eq(Hash(String, String))
  end
end
