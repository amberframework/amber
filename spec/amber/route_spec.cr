require "./../spec_helper"

module Amber
  describe Route do
    it "Initializes correctly with Decendant controller" do
      handler = ->(context : HTTP::Server::Context, action : Symbol) {
          context.response.print "Hey yo world!"
          context.response.close
      }
      request = HTTP::Request.new("GET", "/?test=test")
      context = create_context(request)

      route = Route.new("GET", "/", handler)

      route.class.should eq Route
    end
  end
end
