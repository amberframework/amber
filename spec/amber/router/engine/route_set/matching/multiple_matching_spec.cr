require "../../spec_helper"

describe "matching more than once" do
  it "resolves multiple matches by sorting by insertion order" do
    router1 = build do
      add "/get/domains/mine", :my_domains
      add "/get/domains/:id", :a_domain
    end

    router1.find("/get/domains/mine").payload?.should eq :my_domains
    router1.find("/get/domains/32").payload?.should eq :a_domain

    router2 = build do
      add "/get/domains/:id", :a_domain
      add "/get/domains/mine", :my_domains
    end

    router2.find("/get/domains/mine").payload?.should eq :a_domain
    router2.find("/get/domains/32").payload?.should eq :a_domain
  end
end
