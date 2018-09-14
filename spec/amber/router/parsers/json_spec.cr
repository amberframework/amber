require "../../../../spec_helper"

module Amber::Router::Parsers
  describe JSON do
    describe "self.parse" do
      it "should allow a nil body" do
        request = HTTP::Request.new("PUT", "/")
        request.body.should be_nil
        params = JSON.parse(request)
        params.keys.empty?.should be_true
      end

      it "should parse a json body" do
        body = {test: "123"}.to_json
        request = HTTP::Request.new("PUT", "/", nil, body)
        params = JSON.parse(request)
        params["test"].should eq "123"
      end

      it "should contain the whole unparsed body" do
        body = {
          id:      1234,
          name:    "John",
          email:   "john.doe@example.com",
          age:     21,
          alive:   true,
          address: {
            street:   "4540 High Meadow Lane",
            city:     "Bloomsburg",
            state:    "PA",
            zip_code: "17815",
            location: [40.198196, -101.616699],
          },
        }.to_json
        request = HTTP::Request.new("PUT", "/", nil, body)
        params = Amber::Router::Parsers::JSON.parse(request)
        pp params
        params["_json"].should eq body
      end
    end
  end
end
