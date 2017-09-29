require "../../../spec_helper"

module Amber::Validators
  describe BaseRule do
    describe "#apply" do
      it "raises error when missing field" do
        params = HTTP::Params.parse("")
        rule = BaseRule.new("field", "") do
          false
        end

        expect_raises Exceptions::Validator::InvalidParam do
          rule.apply(params)
        end
      end

      it "returns true for given block" do
        params = HTTP::Params.parse("field=val")
        rule = BaseRule.new("field", "") do
          true
        end

        rule.apply(params).should be_true
      end

      it "returns false for the given block" do
        params = HTTP::Params.parse("field=val")
        rule = BaseRule.new("field", "") do
          false
        end

        rule.apply(params).should be_falsey
      end
    end

    describe "#error" do
      it "returns default error message" do
        params = HTTP::Params.parse("field=val")
        error_message = "Field field is required"
        rule = BaseRule.new("field", nil) do
          false
        end

        rule.apply(params)

        rule.error.should eq Error.new("field", "val", "Field field is required")
      end

      it "returns the given error message" do
        params = HTTP::Params.parse("field=val")
        error_message = "You must provide this field"
        rule = BaseRule.new("field", error_message) do
          false
        end

        rule.apply(params)

        rule.error.should eq Error.new("field", "val", error_message)
      end
    end
  end

  describe OptionalRule do
    describe "#apply" do
      it "does not apply rule when field is missing" do
        params = HTTP::Params.parse("")
        error_message = "You must provide this field"
        rule = OptionalRule.new("field", error_message) do
          false
        end

        rule.apply(params).should be_true
      end

      it "applies rule when field is present" do
        params = HTTP::Params.parse("field=val")
        error_message = "You must provide this field"
        rule = OptionalRule.new("field", error_message) do
          true
        end

        rule.apply(params).should be_true
      end
    end
  end

  describe Params do
    describe "#validation" do
      it "validates required field" do
        http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        result = validator.validation do
          required(:name) { |v| v.str? & !v.empty? }
          required("last_name") { |v| v.str? & !v.empty? }
        end

        validator.valid?.should be_true
        validator.errors.size.should eq 0
      end

      context "optional params" do
        context "when missing" do
          it "does not validate optional field" do
            http_params = HTTP::Params.parse("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            result = validator.validation do
              optional(:name) { |v| v.empty? }
              required("last_name") { |v| v.empty? }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when present" do
          it "validates optional field" do
            http_params = HTTP::Params.parse("name=")
            validator = Validators::Params.new(http_params)

            result = validator.validation do
              optional(:name) { |v| !v.empty? }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end
        end
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
