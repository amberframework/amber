require "../../spec_helper"

module Amber::Schema::ContractCompleteness
  class ConditionalSchema < Definition
    field :kind, String, required: true, enum: ["business", "individual"]

    when_field :kind, "business" do
      field :company_name, String, required: true, min_length: 2
      field :tax_id, String, required: true
    end

    when_field :kind, "individual" do
      field :first_name, String, required: true
      field :last_name, String, required: true
    end
  end

  class PresentSchema < Definition
    field :discount_code, String

    when_present :discount_code do
      field :discount_amount, Float64, required: true, min: 0.0
      field :discount_type, String, required: true, enum: ["fixed", "percentage"]
    end
  end

  class TogetherSchema < Definition
    field :latitude, Float64
    field :longitude, Float64
    requires_together :latitude, :longitude
  end

  class OneOfSchema < Definition
    field :email, String
    field :phone, String
    requires_one_of :email, :phone
  end

  class CollectionSchema < Definition
    field :numbers, Array(Int32), required: true
    field :scores, Hash(String, Int32), required: true
  end

  class SingleCoercionSchema < Definition
    field :name, String, required: true
  end

  describe "complete schema contracts" do
    it "applies enum constraints" do
      ConditionalSchema.new({"kind" => JSON::Any.new("unknown")}).validate.failure?.should be_true
    end

    it "requires only the fields for the matching condition" do
      business = ConditionalSchema.new({
        "kind"         => JSON::Any.new("business"),
        "company_name" => JSON::Any.new("Amber LLC"),
      }).validate
      business.failure?.should be_true
      business.errors.any? { |error| error.field == "tax_id" }.should be_true
      business.errors.none? { |error| error.field == "first_name" }.should be_true

      individual = ConditionalSchema.new({
        "kind"       => JSON::Any.new("individual"),
        "first_name" => JSON::Any.new("Amber"),
        "last_name"  => JSON::Any.new("Grant"),
      }).validate
      individual.success?.should be_true
    end

    it "applies when-present requirements only when the trigger exists" do
      PresentSchema.new({} of String => JSON::Any).validate.success?.should be_true
      result = PresentSchema.new({"discount_code" => JSON::Any.new("SAVE")}).validate
      result.failure?.should be_true
      result.errors.map(&.field).should contain("discount_amount")
      result.errors.map(&.field).should contain("discount_type")
    end

    it "enforces requires-together and requires-one-of" do
      TogetherSchema.new({"latitude" => JSON::Any.new(42.0)}).validate.failure?.should be_true
      TogetherSchema.new({} of String => JSON::Any).validate.success?.should be_true
      OneOfSchema.new({} of String => JSON::Any).validate.failure?.should be_true
      OneOfSchema.new({"email" => JSON::Any.new("a@example.com")}).validate.success?.should be_true
      OneOfSchema.new({
        "email" => JSON::Any.new("a@example.com"),
        "phone" => JSON::Any.new("123"),
      }).validate.failure?.should be_true
    end

    it "fails closed instead of dropping invalid collection members" do
      result = CollectionSchema.new({
        "numbers" => JSON::Any.new([JSON::Any.new(1_i64), JSON::Any.new("invalid")]),
        "scores"  => JSON::Any.new({"a" => JSON::Any.new(1_i64), "b" => JSON::Any.new("invalid")}),
      }).validate
      result.failure?.should be_true
      result.errors.map(&.field).should contain("numbers")
      result.errors.map(&.field).should contain("scores")
    end

    it "keeps mutable validation state isolated between concurrent requests" do
      channel = Channel(Tuple(String, Bool, Array(String))).new

      50.times do |index|
        spawn do
          Fiber.yield
          kind = index.even? ? "business" : "individual"
          data = if kind == "business"
                   {
                     "kind"         => JSON::Any.new(kind),
                     "company_name" => JSON::Any.new("Amber #{index}"),
                     "tax_id"       => JSON::Any.new("T-#{index}"),
                   }
                 else
                   {
                     "kind"       => JSON::Any.new(kind),
                     "first_name" => JSON::Any.new("Amber"),
                     "last_name"  => JSON::Any.new(index.to_s),
                   }
                 end
          schema = ConditionalSchema.new(data)
          result = schema.validate
          channel.send({kind, result.success?, schema.errors.map(&.field)})
        end
      end

      50.times do
        kind, success, errors = channel.receive
        success.should be_true, "#{kind} request received errors from another validation: #{errors}"
        errors.should be_empty
      end
    end

    it "normalizes a source value once and reuses it in typed getters" do
      calls = 0
      TypeCoercion.register("String") do |value|
        calls += 1
        value.as_s?.try { |string| JSON::Any.new(string) }
      end

      schema = SingleCoercionSchema.new({"name" => JSON::Any.new("Amber")})
      schema.validate.success?.should be_true
      calls.should eq(1)
      schema.name.should eq("Amber")
      calls.should eq(1)
    ensure
      TypeCoercion.clear_custom_coercions
    end
  end
end
