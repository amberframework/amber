require "../../spec_helper"

describe "routes with optional segments" do
  it "routes two different paths declared with an optional segment" do
    router = build do
      add "/get/users(/:id/children)", :people_path
    end

    result = router.find "/get/users"
    result.payload?.should eq :people_path

    result = router.find "/get/users/3/children"
    result.payload?.should eq :people_path
  end
end
