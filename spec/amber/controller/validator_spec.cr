require "../../../spec_helper"
require "http"

module Amber
  module Controller
    describe Params::Validator do
      describe "#validate" do
        it "validates required field" do
          http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
          validator = Params::Validator.new(http_params)

          result = validator.validation do
            required("name") { |v| v.str? & !v.empty? }
            required("last_name") { |v| v.str? & !v.empty? }
          end

          puts validator.errors

          result.valid?.should eq true
        end

        # it "returns a hash of the elements validated" do
        #   http_params = HTTP::Params.parse("name=elias&last_name=perez&middle=j")
        #   compare = {} of String => String
        #   compare = {"name" => "elias", "last_name" => "perez"}
        #   controller = Base.new
        #   controller.params = http_params

        #   user = controller.validate do
        #     required("name") { |v| v.str? & !v.empty? }
        #     required("last_name") { |v| v.str? & !v.empty? }
        #   end

        #   user.params.should eq compare
        # end
      end

      # describe "#required" do
      #   it "returns true for all predicates" do
      #     http_params = HTTP::Params.parse("name=elias&last_name=perez")
      #     controller = Base.new
      #     controller.params = http_params

      #     result = controller.required("name") { |v| v.str? & !v.empty? & !v.email? }

      #     result.should eq true
      #   end

      #   it "returns false if one predicate is false" do
      #     http_params = HTTP::Params.parse("name=elias&last_name=perez")
      #     controller = Base.new
      #     controller.params = http_params

      #     result = controller.required("name") { |v| v.str? & !v.empty? & v.email? }

      #     result.should eq false
      #   end

      #   it "returns false if key does not exists" do
      #     http_params = HTTP::Params.parse("name=elias&last_name=perez")
      #     controller = Base.new

      #     result = controller.required("name") { |v| v.str? & !v.empty? & v.email? }

      #     result.should eq false
      #   end
      # end
    end
  end
end
