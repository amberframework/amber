require "../../spec_helper"

describe "glob routes" do
  it "resolves glob urls" do
    router = build do
      add "/get/products/*", :products_slug
    end

    router.find("/get/products/fancy_hairdoo").payload?.should eq :products_slug
  end

  it "resolves glob urls with a suffix" do
    router = build do
      add "/get/products/*/with_name", :products_slug_with_name
    end

    router.find("/get/products/fancy_hairdoo/with_name").payload?.should eq :products_slug_with_name
  end

  it "handles multiple variable length routes nested under a glob" do
    router = build do
      add "/get/*/two/test", :test_two
      add "/get/*/test", :test_one
    end

    router.find("/get/products/test").payload?.should eq :test_one
    router.find("/get/products/two/test").payload?.should eq :test_two
  end
end
