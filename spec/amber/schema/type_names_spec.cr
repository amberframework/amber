require "../../spec_helper"

module Amber::Schema
  describe TypeNames do
    describe ".array_element_type" do
      it "returns the text between Array( and the final )" do
        TypeNames.array_element_type("Array(Int32)").should eq "Int32"
        TypeNames.array_element_type("Array(Hash(String, Int32))").should eq "Hash(String, Int32)"
        TypeNames.array_element_type("Array(()").should eq "("
      end

      it "returns nil for an empty argument, another type, or an argument across lines" do
        TypeNames.array_element_type("Array()").should be_nil
        TypeNames.array_element_type("Int32").should be_nil
        TypeNames.array_element_type("Array(Int32").should be_nil
        TypeNames.array_element_type("Array(Int\n32)").should be_nil
        TypeNames.array_element_type("MyArray(Int32)").should be_nil
      end
    end

    describe ".string_hash_value_type" do
      it "returns the text between Hash(String,  and the final )" do
        TypeNames.string_hash_value_type("Hash(String, Bool)").should eq "Bool"
        TypeNames.string_hash_value_type("Hash(String, Array(Int32))").should eq "Array(Int32)"
      end

      it "returns nil for other key types and spacing" do
        TypeNames.string_hash_value_type("Hash(Int32, Bool)").should be_nil
        TypeNames.string_hash_value_type("Hash(String,Bool)").should be_nil
        TypeNames.string_hash_value_type("Hash(String, )").should be_nil
      end
    end
  end
end

module Amber::Schema
  describe TypeCoercion do
    describe ".coerce with generic type names" do
      it "coerces each element of an Array(...) type" do
        value = JSON::Any.new([JSON::Any.new("1"), JSON::Any.new("2")])
        TypeCoercion.coerce(value, "Array(Int32)").should eq JSON::Any.new([JSON::Any.new(1), JSON::Any.new(2)])
      end

      it "coerces each value of a Hash(String, ...) type" do
        value = JSON::Any.new({"a" => JSON::Any.new("true")})
        TypeCoercion.coerce(value, "Hash(String, Bool)").should eq JSON::Any.new({"a" => JSON::Any.new(true)})
      end

      it "returns nil for a Hash keyed by anything but String" do
        value = JSON::Any.new({"a" => JSON::Any.new("1")})
        TypeCoercion.coerce(value, "Hash(Int32, Int32)").should be_nil
      end
    end
  end
end
