require "../../spec_helper"

module Amber::Validators
  describe Params do
    describe "#validation" do
      context "JSON param" do
        it "parses json array as [] of JSON::Any" do
          params = json_params_builder({ x: [ 1, 2, 3 ] }.to_json)
          validator = Validators::Params.new(params)

          validator.validation do
            required(:x)
          end

          validator.validate!["x"].should be_a Array(JSON::Any)
        end
      end

      context "required params" do
        context "when missing" do
          it "is not valid and has 2 errors" do
            validator = Validators::Params.new(params_builder(""))

            validator.validation do
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

            validator.validation do
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

            validator.validation do
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

            validator.validation do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is not valid when param is missing" do
            http_params = params_builder("last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end

          it "is not valid when param is present, but blank" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 2
          end

          it "is valid when param is present, but blank, and allow_blank = true" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
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

            validator.validation do
              optional(:name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
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

            validator.validation do
              optional(:name) { false }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end

          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { false }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name=&last_name= &middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { false }
              optional(:last_name) { false }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is not valid and it has errors when param is present, but blank, and allow_blank = false" do
            http_params = params_builder("name=%20&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
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

            validator.validation do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present" do
            http_params = params_builder("name=asdf&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name=%20&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
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

        validator.validation do
          required("nonexisting") { |v| !v.nil? }
        end

        validator.valid?.should be_false
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

      it "should not present optional fields when param is not present" do
        http_params = params_builder("name=elias&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias"}

        validator.validation do
          required("name") { |v| !v.nil? }
          optional("last_name")
        end

        validator.validate!.should eq result
      end

      it "should present optional fields when param is present" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias", "last_name" => "perez"}

        validator.validation do
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
