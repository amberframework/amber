require "http"
require "../../../spec_helper"

class FakeController < Amber::Controller::Base
  params("User") do
    param email : String, size: (50..50), regex: /\w+@\w+\.\w{2,}/
    param name : String, size: (1..20)
    param age : Int32, gte: 500
    param alive : Bool, in: [true, false]
  end

  def index
    user.valid?
    p user.to_h
    user.valid?
  end
end

module Amber
  describe Controller do
    request = HTTP::Request.new(
      "GET",
      "/?user.address.street=303 Laerence Ave&" \
      "user.address.city=Jersey City&" \
      "user.address.state=NJ&" \
      "user.address.zip_code=60459&" \
      "email=eliasjpr@gmail.com&name=elias&age=37&alive=true"
    )

    request.headers.add("Referer", "")
    context = create_context(request)
    controller = FakeController.new(context)

    it "works" do
      controller.index.should be_true
    end
  end
end
