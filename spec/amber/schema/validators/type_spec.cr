require "../../../spec_helper"

module Amber::Schema
  class TypeValidatorSpecSchema < Definition
  end
end

private def type_valid?(expected_type : String, value : JSON::Any) : Bool
  data = {"field" => value}
  result = Amber::Schema::LegacyResult.new(true, data)
  context = Amber::Schema::Validator::Context.new(data, result, Amber::Schema::TypeValidatorSpecSchema.new(data))
  Amber::Schema::Validator::Type.new("field", expected_type).validate(context)
  result.success
end

describe Amber::Schema::Validator::Type do
  describe "#validate" do
    it "accepts an array for any type name that starts with Array(" do
      type_valid?("Array(Int32)", JSON::Any.new([JSON::Any.new(1_i64)])).should be_true
      type_valid?("Array(", JSON::Any.new([] of JSON::Any)).should be_true
      type_valid?("Array(Int32)", JSON::Any.new("x")).should be_false
    end

    it "accepts a hash for any type name that starts with Hash(" do
      type_valid?("Hash(String, Int32)", JSON::Any.new({} of String => JSON::Any)).should be_true
      type_valid?("Hash(String, Int32)", JSON::Any.new([] of JSON::Any)).should be_false
    end
  end
end
