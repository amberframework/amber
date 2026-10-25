require "../../spec_helper"

# Applies legacy rules exactly as the deprecated `Params#validation` entry
# point does. The rule engine stays covered for V2 migration compatibility
# while the suite itself compiles without deprecation warnings.
private def apply_legacy_rules(validator : Amber::Validators::Params, &) : Amber::Validators::Params
  with Amber::Validators::ValidationBuilder.new(validator) yield
  validator
end

module Amber::Validators
  describe Params do
    describe "#validation" do
      it "remains deprecated in favor of Amber::Schema controller contracts" do
        {% begin %}
          {% validation_method = Amber::Validators::Params.methods.find { |method| method.name == "validation" } %}
          {% deprecation = validation_method && validation_method.annotation(Deprecated) %}
          {{ deprecation ? deprecation[0] : nil }}.should eq(
            "Use Amber::Schema controller contracts; legacy params validation remains available for V2 migration compatibility"
          )
        {% end %}
      end
    end

    describe "legacy validation rules" do
      context "required params" do
        context "when missing" do
          it "is not valid and has 2 errors" do
            validator = Validators::Params.new(params_builder(""))

            apply_legacy_rules(validator) do
              required(:name) { true }
              required("last_name") { true }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 2
          end
        end

        context "when params present" do
          it "is valid and there are no errors" do
            http_params = params_builder("name=elias&last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              required(:name) { |v| !v.nil? }
              required("last_name") { |v| !v.nil? }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when one of the params is invalid" do
          it "is not valid and it has errors" do
            http_params = params_builder("name=&last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              required(:name) { |v| !v.empty? }
              required("last_name") { |v| !v.nil? }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
            validator.errors.first.param.should eq "name"
          end
        end

        context "when no block passed" do
          it "is valid and there are no errors when param is present and not blank" do
            http_params = params_builder("name=elias&last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is not valid when param is missing" do
            http_params = params_builder("last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end

          it "is not valid when param is present, but blank" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 2
          end

          it "is valid when param is present, but blank, and allow_blank = true" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              required(:name, allow_blank: true)
              required(:last_name, allow_blank: true)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end
      end

      context "optional params" do
        context "when block evaluates to true" do
          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name) { true }
              optional(:last_name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when block evaluates to false" do
          it "is not valid and it has errors if param is present and not blank" do
            http_params = params_builder("name=asdf")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name) { false }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end

          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name) { false }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name=&last_name= &middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name) { false }
              optional(:last_name) { false }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is not valid and it has errors when param is present, but blank, and allow_blank = false" do
            http_params = params_builder("name=%20&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name, allow_blank: false) { false }
              optional(:last_name, allow_blank: false) { false }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 2
          end
        end

        context "when no block passed" do
          it "is valid and there are no errors when param is not present" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present" do
            http_params = params_builder("name=asdf&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name=%20&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            apply_legacy_rules(validator) do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end
      end

      context "casting" do
        it "returns false for the given block" do
          params = params_builder("name=john&number=1&price=3.45&list=[1,2,3]")
          validator = Validators::Params.new(params)
          apply_legacy_rules(validator) do
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

    describe "#valid?" do
      it "returns false with invalid fields" do
        http_params = params_builder("name=john&last_name=doe&middle=j")
        validator = Validators::Params.new(http_params)

        apply_legacy_rules(validator) do
          required("name") { |v| v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.valid?.should be_false
      end

      it "returns false when key does not exist" do
        http_params = params_builder("name=elias")
        validator = Validators::Params.new(http_params)

        apply_legacy_rules(validator) do
          required("nonexisting") { |v| !v.nil? }
        end

        validator.valid?.should be_false
      end

      it "returns true with valid fields" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        apply_legacy_rules(validator) do
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

        apply_legacy_rules(validator) do
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

        apply_legacy_rules(validator) do
          required("name") { |v| !v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.validate!.should eq result
      end

      it "should not present optional fields when param is not present" do
        http_params = params_builder("name=elias&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias"}

        apply_legacy_rules(validator) do
          required("name") { |v| !v.nil? }
          optional("last_name")
        end

        validator.validate!.should eq result
      end

      it "should present optional fields when param is present" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias", "last_name" => "perez"}

        apply_legacy_rules(validator) do
          required("name") { |v| !v.nil? }
          optional("last_name")
        end

        validator.validate!.should eq result
      end
    end

    describe "#to_unsafe_h" do
      it "returns request raw_params as a hash" do
        http_params = params_builder("first_name=elias&last_name=perez")
        validator = Validators::Params.new(http_params)

        validator.to_h.should eq({} of String => String)

        validator.to_unsafe_h.should eq({"first_name" => "elias", "last_name" => "perez"})
      end
    end
  end
end
