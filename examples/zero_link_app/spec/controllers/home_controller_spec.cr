require "../spec_helper"

describe HomeController do
  describe "GET /" do
    it "responds successfully" do
      response = get("/")
      assert_response_success(response)
    end
  end
end
