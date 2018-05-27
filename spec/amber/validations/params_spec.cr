require "../../spec_helper"

module Amber::Validators
  describe Params do
    describe "#validation" do
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
          it "is valid and there is no errors" do
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
      end

      context "optional params" do
        context "when missing" do
          it "is valid and there is no errors" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { |v| !v.nil? }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when block evaluates to true" do
          it "passes validation and there is no errors" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when block evaluates to false" do
          it "fails validation and it has errors" do
            http_params = params_builder("name=")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { false }
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
    end
  end
end
