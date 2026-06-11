require "../spec_helper"

describe "resolving optional segments in paths" do
  it "does not alter paths without optionals" do
    path = "/users/:id"
    expected = [path]
    actual = Amber::Router::Parsers::OptionalSegmentResolver.resolve(path)
    actual.should eq expected
  end

  it "resolves one optional properly" do
    path = "/users/:id(/children)/"
    expected = [
      "/users/:id/",
      "/users/:id/children/",
    ]
    actual = Amber::Router::Parsers::OptionalSegmentResolver.resolve(path)
    actual.should eq expected
  end

  it "resolves one nested optional properly" do
    path = "/users/:id(/children(/grandchildren))/"
    expected = [
      "/users/:id/",
      "/users/:id/children/",
      "/users/:id/children/grandchildren/",
    ]

    actual = Amber::Router::Parsers::OptionalSegmentResolver.resolve(path)
    actual.should eq expected
  end

  it "resolves two adjacent optionals properly" do
    path = "/users/:id(/children)(/grandchildren)/"
    expected = [
      "/users/:id/",
      "/users/:id/grandchildren/",
      "/users/:id/children/",
      "/users/:id/children/grandchildren/",
    ]

    actual = Amber::Router::Parsers::OptionalSegmentResolver.resolve(path)
    actual.should eq expected
  end

  it "raises on mismatched parenthesis" do
    path = "/users/(:id"

    expect_raises Exception, /Could not find matching closing parenthesis:/ do
      Amber::Router::Parsers::OptionalSegmentResolver.resolve(path)
    end
  end
end
