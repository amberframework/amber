require "../spec_helper"

describe Amber::Router::RouteSet do
  describe "#find_routes" do
    it "returns an array of matches" do
      route_set = build do
        add "foo/bar", :foo_bar
        add "foo", :foo_get
        add "foo", :foo_post
        add "foo", :foo_delete
      end

      matches = route_set.find_routes("foo")
      matches.size.should eq 3

      matches.map(&.payload?).should eq [:foo_get, :foo_post, :foo_delete]
    end
  end
end
