require "../../spec_helper"

describe "glob parameters" do
  it "renders glob parameters" do
    router = build do
      add "/get/products/*slug/dp/:id", :product
    end

    result = router.find("/get/products/Winter-Windproof-Trapper-Hat/dp/B01J7DAMCQ")
    result.params.should eq({
      "id"   => "B01J7DAMCQ",
      "slug" => "Winter-Windproof-Trapper-Hat",
    })
  end

  it "renders glob parameters which span segments" do
    router = build do
      add "/get/categories/*categories/products", :categories_products
    end

    result = router.find("/get/categories/hats/scarfs/mittens/gloves/products")
    result.params.should eq({
      "categories" => "hats/scarfs/mittens/gloves",
    })
  end

  it "renders a glob parameter which gobbles up the rest of a url" do
    router = build do
      add "/get/*", :spa_route
    end

    result = router.find("/get/products/1")
    result.payload?.should eq :spa_route
  end

  it "renders a named glob parameter which gobbles up the rest of a url" do
    router = build do
      add "/get/*url", :spa_route
    end

    router.find("/get/products/1").params.should eq({
      "url" => "products/1",
    })
  end

  it "URI decodes the parameters" do
    router = build do
      add "/get/categories/*categories/products", :categories_products
    end

    result = router.find "/get/categories/hats/scarfs%20&%20mittens/products"
    result.params.should eq({"categories" => "hats/scarfs & mittens"})
  end
end
