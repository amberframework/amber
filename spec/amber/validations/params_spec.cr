require "../../../spec_helper"

module Amber
  describe Validators::Params do
    describe "#validation" do
      it "validates required field" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        result = validator.validation do
          required(:name) { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.errors.size.should eq 0
        validator.valid?.should be_true
      end
    end

    describe "#valid?" do
      it "returns false with invalid fields" do
        http_params = HTTP::Params.parse("name=john&last_name=doe&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.valid?.should be_false
      end

      it "returns false when key does not exist" do
        http_params = HTTP::Params.parse("name=elias")
        validator = Validators::Params.new(http_params)
        result = {"nonexisting" => {nil, "Param [nonexisting] does not exist."}}

        validator.validation do
          required("nonexisting") { |v| v.str? & !v.empty? }
        end

        expect_raises Exceptions::Validator::InvalidParam do
          validator.valid?
        end
      end

      it "returns true with valid fields" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.valid?.should be_true
      end
    end

    describe "#validate!" do
      it "raises error on failed validation" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| v.str? & v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        expect_raises Exceptions::Validator::ValidationFailed do
          validator.validate!
        end
      end

      it "returns validated params on successful validation" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias", "last_name" => "perez"}

        validator.validation do
          required("name") { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.validate!.should eq result
      end
    end
  end
end
