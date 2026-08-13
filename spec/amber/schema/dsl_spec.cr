require "../../spec_helper"

module Amber::Schema::DSLSpec
  class ShorthandSchema < Definition
    include DSL

    string :name, required: true, min_length: 2
    integer :age, min: 0
    float :score, max: 1.0
    boolean :active, default: true
    array :tags, of: String
    hash :metadata
    datetime :published_at

    validates_length :name, min: 3, max: 20
    validates_range :age, min: 1, max: 120
    validates_range :score, min: 0.0, max: 1.0
    validates_pattern :name, "^[A-Za-z]+$"
    validates_enum :age, [2, 3, 4]
  end

  class AddressSchema < Definition
    field :city, String, required: true
  end

  class EmbeddedSchema < Definition
    include DSL

    embedded :address, AddressSchema, required: true
    embedded_array :previous_addresses, AddressSchema
  end

  describe DSL do
    it "delegates shorthand fields to the authoritative field contract" do
      schema = ShorthandSchema.new({
        "name"         => JSON::Any.new("Amber"),
        "age"          => JSON::Any.new("2"),
        "score"        => JSON::Any.new("0.8"),
        "tags"         => JSON::Any.new("crystal,web"),
        "metadata"     => JSON::Any.new({"kind" => JSON::Any.new("guide")}),
        "published_at" => JSON::Any.new("2026-08-13T10:00:00Z"),
      })

      schema.validate.success?.should be_true
      schema.name.should eq("Amber")
      schema.age.should eq(2)
      schema.score.should eq(0.8)
      schema.active.should be_true
      schema.tags.should eq(["crystal", "web"])
    end

    it "applies shorthand validators through normal field options" do
      result = ShorthandSchema.new({
        "name"  => JSON::Any.new("A1"),
        "age"   => JSON::Any.new(9_i64),
        "score" => JSON::Any.new(1.5),
      }).validate

      result.failure?.should be_true
      result.errors.map(&.code).should contain("invalid_length")
      result.errors.map(&.code).should contain("invalid_format")
      result.errors.map(&.code).should contain("invalid_enum_value")
      result.errors.map(&.code).should contain("out_of_range")
    end

    it "validates embedded objects and arrays" do
      result = EmbeddedSchema.new({
        "address"            => JSON::Any.new({"city" => JSON::Any.new("Boston")}),
        "previous_addresses" => JSON::Any.new([
          JSON::Any.new({"city" => JSON::Any.new("Portsmouth")}),
          JSON::Any.new({} of String => JSON::Any),
        ]),
      }).validate

      result.failure?.should be_true
      result.errors.map(&.field).should contain("previous_addresses[1].city")
    end
  end
end
