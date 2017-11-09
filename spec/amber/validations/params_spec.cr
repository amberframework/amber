require "../../../spec_helper"

module Amber::Validators
  describe BaseRule do
    describe "#apply" do
      it "raises error when missing field" do
        params = params_builder("")
        rule = BaseRule.new("field", "") do
          false
        end

        expect_raises Exceptions::Validator::InvalidParam do
          rule.apply(params)
        end
      end

      it "returns true for given block" do
        params = params_builder("field=val")
        rule = BaseRule.new("field", "") do
          true
        end

        rule.apply(params).should be_true
      end

      it "returns false for the given block" do
        params = params_builder("field=val")
        rule = BaseRule.new("field", "") do
          false
        end

        rule.apply(params).should be_falsey
      end
    end

    describe "#error" do
      it "returns default error message" do
        params = params_builder("field=val")
        error_message = "Field field is required"
        rule = BaseRule.new("field", nil) do
          false
        end

        rule.apply(params)

        rule.error.should eq Error.new("field", "val", "Field field is required")
      end

      it "returns the given error message" do
        params = params_builder("field=val")
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
        params = params_builder("")
        error_message = "You must provide this field"
        rule = OptionalRule.new("field", error_message) do
          true
        end

        rule.apply(params).should be_true
      end

      it "applies rule when field is present" do
        params = params_builder("field=val")
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
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        result = validator.validation do
          required(:name) { |v| !v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.valid?.should be_true
        validator.errors.size.should eq 0
      end

      context "optional params" do
        context "when missing" do
          it "does not validate optional field" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            result = validator.validation do
              optional(:name) { |v| !v.nil? }
              required("last_name") { |v| !v.nil? }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when present" do
          it "validates optional field" do
            http_params = params_builder("name=")
            validator = Validators::Params.new(http_params)

            result = validator.validation do
              optional(:name) { |v| v.nil? }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end
        end

        context "casting" do
          it "returns false for the given block" do
            params = params_builder("name=john&number=1&price=3.45&list=[1,2,3]")
            validator = Validators::Params.new(params)
            validator.validation do
              required(:name) { |f| !f.to_s.empty? }
              required(:number) { |f| f.as(String).to_i > 0 }
              required(:price) { |f| f.as(String).to_f == 3.45 }
              required(:list) do |f|
                list = JSON.parse(f.as(String)).as_a
                (list == [1, 2, 3] && !list.includes? 6)
              end
            end

            validator.valid?.should be_truthy
          end
        end
      end
    end

    describe "#valid?" do
      it "returns false with invalid fields" do
        http_params = params_builder("name=john&last_name=doe&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.valid?.should be_false
      end

      it "returns false when key does not exist" do
        http_params = params_builder("name=elias")
        validator = Validators::Params.new(http_params)
        result = {"nonexisting" => {nil, "Param [nonexisting] does not exist."}}

        validator.validation do
          required("nonexisting") { |v| !v.nil? }
        end

        expect_raises Exceptions::Validator::InvalidParam do
          validator.valid?
        end
      end

      it "returns true with valid fields" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| !v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.valid?.should be_true
      end
    end

    describe "#validate!" do
      it "raises error on failed validation" do
        http_params = params_builder("name=&last_name=&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| !v.to_s.empty? }
          required("last_name") { |v| !v.to_s.empty? }
        end

        expect_raises Exceptions::Validator::ValidationFailed do
          validator.validate!
        end
      end

      it "returns validated params on successful validation" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias", "last_name" => "perez"}

        validator.validation do
          required("name") { |v| !v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.validate!.should eq result
      end
    end
  end
end

def params_builder(body = "")
  params = Amber::Router::Params.new
  return params if body.empty?

  body.tr("?", "").split("&").each_with_object(params) do |item, params|
    key, value = item.split("=")
    params[key] = value
  end
end
