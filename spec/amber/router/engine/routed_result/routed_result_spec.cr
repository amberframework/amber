require "../spec_helper"

def terminal_segment
  Amber::Router::TerminalSegment(Symbol).new(
    :route,
    "/full/path"
  )
end

def found_result
  Amber::Router::RoutedResult(Symbol).new terminal_segment
end

def not_found_result
  Amber::Router::RoutedResult(Symbol).new nil
end

describe Amber::Router::RoutedResult do
  context "found?" do
    it "is false when no terminal segment is provided" do
      not_found_result.found?.should be_false
    end

    it "is true when a route is found" do
      found_result.found?.should be_true
    end
  end

  context "payload?" do
    it "is nil when no route is found" do
      not_found_result.payload?.should be_nil
    end

    it "returns the payload when it is found" do
      found_result.payload?.should eq :route
    end
  end

  context "params via []" do
    it "allows getting parameters" do
      result = found_result
      result["name"] = "john"
      result.params["name"].should eq "john"
      result["name"].should eq "john"
    end
  end

  context "path" do
    it "allows retrieving the matched path" do
      router = build do
        add "/get/users/:id", :user
      end

      result = router.find("/get/users/3")
      result.found?.should be_true
      result.path.should eq "/get/users/:id"
    end
  end
end
