require "../../spec_helper"

module Amber::Router
  # A rule a route parameter can carry: an even, in-range page number.
  private struct EvenPageNumber
    include ParamConstraint

    def matches?(segment : String) : Bool
      if page_number = segment.to_i?
        page_number.even? && page_number > 0
      else
        false
      end
    end

    def to_s(io : IO) : Nil
      io << "even_page_number"
    end
  end

  private def self.route_with(rule) : Route
    Route.new("GET", "/items/:value", ->(_context : HTTP::Server::Context) { }, :show, :web, Scope.new, "ItemsController", {"value" => rule})
  end

  private def self.router_finds?(rule, segment : String) : Bool
    router = Router.new
    router.add route_with(rule)
    router.match_by_request(HTTP::Request.new("GET", "/items/#{segment}")).found?
  end

  describe ParamConstraints do
    describe "NUMERIC" do
      it "matches a whole segment of ASCII digits" do
        ParamConstraints::NUMERIC.matches?("0").should be_true
        ParamConstraints::NUMERIC.matches?("1234567890").should be_true
      end

      it "rejects empty, mixed, signed and non-ASCII digit segments" do
        ParamConstraints::NUMERIC.matches?("").should be_false
        ParamConstraints::NUMERIC.matches?("12a").should be_false
        ParamConstraints::NUMERIC.matches?("a12").should be_false
        ParamConstraints::NUMERIC.matches?("-12").should be_false
        ParamConstraints::NUMERIC.matches?("١٢").should be_false
      end

      it "routes digits and refuses the rest" do
        router_finds?(:numeric, "42").should be_true
        router_finds?(:numeric, "42x").should be_false
      end
    end

    describe "CharacterRun#with_length" do
      it "accepts exactly the given number of characters" do
        three_digits = ParamConstraints::NUMERIC.with_length(3)
        three_digits.matches?("042").should be_true
        three_digits.matches?("42").should be_false
        three_digits.matches?("4242").should be_false
      end

      it "accepts a range and an open upper bound" do
        ParamConstraints::HEX.with_length(2, 4).matches?("abcd").should be_true
        ParamConstraints::HEX.with_length(2, 4).matches?("abcde").should be_false
        ParamConstraints::HEX.with_length(0, nil).matches?("").should be_true
      end

      it "labels the length in route listings" do
        ParamConstraints::NUMERIC.to_s.should eq "numeric"
        ParamConstraints::NUMERIC.with_length(3).to_s.should eq "numeric{3}"
        ParamConstraints::HEX.with_length(2, 4).to_s.should eq "hex{2,4}"
        ParamConstraints::HEX.with_length(2, nil).to_s.should eq "hex{2,}"
      end

      it "refuses lengths no segment could have" do
        expect_raises(ArgumentError, "below min_length") { ParamConstraints::NUMERIC.with_length(4, 2) }
        expect_raises(ArgumentError, "negative") { ParamConstraints::NUMERIC.with_length(-1) }
      end
    end

    describe "CharacterRun.new" do
      it "builds a rule from characters and ranges" do
        ticket_code = ParamConstraints::CharacterRun.new("ticket_code", 'A'..'Z', '_')
        ticket_code.matches?("ABC_DEF").should be_true
        ticket_code.matches?("abc").should be_false
        ticket_code.matches?("ÄBC").should be_false
      end

      it "leaves out the end of an exclusive range" do
        a_to_c = ParamConstraints::CharacterRun.new("a_to_c", 'a'...'d')
        a_to_c.matches?("abc").should be_true
        a_to_c.matches?("abcd").should be_false
      end

      it "refuses characters outside ASCII and empty ranges" do
        expect_raises(ArgumentError, "outside ASCII") { ParamConstraints::CharacterRun.new("accented", 'é') }
        expect_raises(ArgumentError, "is empty") { ParamConstraints::CharacterRun.new("backwards", 'z'..'a') }
      end
    end

    describe "SLUG" do
      it "matches lowercase words joined by single hyphens" do
        ParamConstraints::SLUG.matches?("hello").should be_true
        ParamConstraints::SLUG.matches?("hello-amber-2").should be_true
      end

      it "rejects capitals, edge hyphens, doubled hyphens and other characters" do
        ParamConstraints::SLUG.matches?("").should be_false
        ParamConstraints::SLUG.matches?("Hello").should be_false
        ParamConstraints::SLUG.matches?("-hello").should be_false
        ParamConstraints::SLUG.matches?("hello-").should be_false
        ParamConstraints::SLUG.matches?("hello--world").should be_false
        ParamConstraints::SLUG.matches?("hello_world").should be_false
        ParamConstraints::SLUG.matches?("hello%20world").should be_false
      end

      it "routes slugs" do
        router_finds?(:slug, "my-post-123").should be_true
        router_finds?(:slug, "My-Post").should be_false
      end
    end

    describe "UUID" do
      it "matches the hyphenated form in either letter case" do
        ParamConstraints::UUID.matches?("550e8400-e29b-41d4-a716-446655440000").should be_true
        ParamConstraints::UUID.matches?("550E8400-E29B-41D4-A716-446655440000").should be_true
      end

      it "rejects other shapes" do
        ParamConstraints::UUID.matches?("550e8400e29b41d4a716446655440000").should be_false
        ParamConstraints::UUID.matches?("550e8400-e29b-41d4-a716-44665544000").should be_false
        ParamConstraints::UUID.matches?("550e8400-e29b-41d4-a716-4466554400000").should be_false
        ParamConstraints::UUID.matches?("550e8400-e29b-41d4-a716_446655440000").should be_false
        ParamConstraints::UUID.matches?("g50e8400-e29b-41d4-a716-446655440000").should be_false
      end

      it "routes UUIDs" do
        router_finds?(ParamConstraints::UUID, "550e8400-e29b-41d4-a716-446655440000").should be_true
        router_finds?(ParamConstraints::UUID, "not-a-uuid").should be_false
      end
    end

    describe "OneOf" do
      it "matches only the listed values" do
        state = ParamConstraints::OneOf.new("draft", "published")
        state.matches?("draft").should be_true
        state.matches?("archived").should be_false
        state.to_s.should eq "one_of(draft|published)"
      end

      it "hands out a copy of its values" do
        state = ParamConstraints::OneOf.new("draft")
        state.list_of_values << "published"
        state.list_of_values.should eq ["draft"]
        state.to_s.should eq "one_of(draft)"
      end
    end

    describe "custom rules" do
      it "routes through a block" do
        json_file = ParamConstraints::Custom.new("json_file", &.ends_with?(".json"))
        json_file.to_s.should eq "json_file"
        router_finds?(json_file, "report.json").should be_true
        router_finds?(json_file, "report.csv").should be_false
      end

      it "routes through a type that includes ParamConstraint" do
        router_finds?(EvenPageNumber.new, "4").should be_true
        router_finds?(EvenPageNumber.new, "3").should be_false
        router_finds?(EvenPageNumber.new, "four").should be_false
      end

      it "sees the segment the router reads in place" do
        router = RouteSet(Symbol).new
        router.add "/a/:first/b/:second", :pair, {first: EvenPageNumber.new, second: :numeric}
        router.find("/a/2/b/9").payload?.should eq :pair
        router.find("/a/3/b/9").found?.should be_false
      end
    end

    describe ".normalize" do
      it "keys rules by parameter name and resolves preset symbols" do
        normalized = ParamConstraints.normalize({:id => :numeric, "key" => ParamConstraints::UUID})
        normalized["id"].should eq ParamConstraints::NUMERIC
        normalized["key"].should eq ParamConstraints::UUID
      end

      it "accepts a named tuple of mixed rule types" do
        normalized = ParamConstraints.normalize({id: :numeric, slug: ParamConstraints::SLUG})
        normalized.keys.should eq ["id", "slug"]
      end

      it "names the known presets when a route names an unknown one" do
        expect_raises(ParamConstraints::UnknownPresetError, "Unknown route parameter constraint :digits. Known presets: :numeric") do
          ParamConstraints.normalize({id: :digits})
        end
      end
    end

    describe "in the routing DSL" do
      it "takes preset symbols and rule values" do
        router = Router.new
        router.draw :web do
          get "/posts/:id", HelloController, :index, {"id" => :numeric}
          get "/tags/:slug", HelloController, :world, {slug: Amber::Router::ParamConstraints::SLUG}
        end

        router.match("GET", "/posts/12").found?.should be_true
        router.match("GET", "/posts/twelve").found?.should be_false
        router.match("GET", "/tags/crystal-lang").found?.should be_true
        router.match("GET", "/tags/Crystal").found?.should be_false
      end

      it "lists each rule by its label" do
        router = Router.new
        router.draw :web do
          get "/posts/:id", HelloController, :index, {"id" => :numeric}
        end

        router.all_routes.first.constraints.should eq({"id" => "numeric"})
      end
    end
  end
end
