require "http"
require "../../../spec_helper"

class FakeController < Amber::Controller::Base
  contract("User") do
    param email : String, length: (50..50), regex: /\w+@\w+\.\w{2,}/
    param name : String, length: (1..20)
    param age : Int32, gte: 58, eq: 24, be: "Age"
    param alive : Bool, be: false
    param childrens : Array(String)
    param childrens_ages : Array(Int32)

    contract("Address", "user.address") do
      param street : String, length: (10..35)
      param city : String, eq: "Jersey City"
      param state : String, in: ["NJ", "NY"]
      param zip_code : String, length: (5..5)

      contract("Location", "user.address.location") do
        param longitude : Int32
        param latitude : Int32
      end
    end
  end
end

module Amber
  describe Controller do
    request = HTTP::Request.new(
      "GET",
      "/?user.address.street=303 Lawrence Ave&" \
      "user.address.city=Jersey City&" \
      "user.address.state=NJ&" \
      "user.address.zip_code=60459&" \
      "user.address.location.latitude=123456.9765&" \
      "user.address.location.longitude=123456.9765&" \
      "email=eliasjprgmail.com&name=elias&age=37&alive=true&" \
      "childrens=camila&childrens=eva&childrens_ages=6&childrens_ages=3"
    )

    controller = build_controller_for(request)

    it "does have have errors" do
      controller.user.valid?.should be_false
      controller.user.errors.empty?.should be_false
      controller.user.errors.size.should eq 5
    end
  end
end

def build_controller_for(request)
  request.headers.add("Referer", "")
  context = create_context(request)
  FakeController.new(context)
end
