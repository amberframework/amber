require "../../../spec_helper"
require "http"

module Amber::Validators
  describe Params do
    describe "#validation" do
      it "validates required field" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Params.new(http_params)

        result = validator.validation do
          required("name") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        result.valid?.should eq true
      end
    end

    describe "#valid?" do
      it "returns false with invalid fields" do
        http_params = HTTP::Params.parse("name=john&last_name=doe&middle=j")
        validator =Params.new(http_params)

        result = validator.validation do
          required("name") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.valid?.should eq false
      end

      it "returns false when key does not exist" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Params.new(http_params)
        result : Tuple(String, String) = {"invalid", "nonexisting does not exist."}

        validator.validation do
          required("nonexisting") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.errors.should contain result
        validator.valid?.should eq false
      end

      it "returns true with valid fields" do
        http_params = HTTP::Params.parse("name=eliaslast_name=perez&middle=j")
        validator = Params.new(http_params)
        result : Tuple(String, String) = {"invalid", "nonexisting does not exist."}

        validator.validation do
          required("nonexisting") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.errors.should contain result
        validator.valid?.should eq false
      end
    end

    describe "#validate!" do
      it "raises error with no validation rules" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Params.new(http_params)

        expect_raises Exceptions::Validator::MissingValidationRules do
          validator.validate!
        end
      end

      it "raises error on failed validation" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Params.new(http_params)

        validator.validation do
          required("name") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        expect_raises Exceptions::Validator::ValidationFailed do
          validator.validate!
        end
      end

      it "returns validated params on successful validation" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Params.new(http_params)
        result : Hash(String, String) = {"invalid", "nonexisting does not exist."}

        validator.validation do
          required("name") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.validate!.should eq result
      end
    end
  end
end
