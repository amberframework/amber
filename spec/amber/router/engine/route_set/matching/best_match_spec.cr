require "../../spec_helper"

private def expect_same_best_match(router, path : String)
  current = router.find(path)
  candidate = router.find_best(path)

  candidate.found?.should eq(current.found?)
  candidate.payload?.should eq(current.payload?)
  candidate.params.should eq(current.params)
end

describe "best-match routing" do
  it "matches fixed, variable, constrained, glob, encoded, and missing paths" do
    router = build do
      add "/get/domains/mine", :my_domains
      add "/get/domains/:id", :a_domain
      add "/get/posts/:page", :numeric_post, {page: /\A\d+\z/}
      add "/get/products/*path", :products_slug
      add "/get/products/*path/with_name", :products_slug_with_name
      add "/get/books/:id/authors/:author_id", :book_author
    end

    %w(
      /get
      /get/domains/mine
      /get/domains/32
      /get/domains/hello%20world
      /get/posts/1
      /get/posts/foo
      /get/products/fancy/hairdo
      /get/products/fancy/hairdo/with_name
      /get/books/3/authors/7
      /get/books/3/pages
    ).each { |path| expect_same_best_match(router, path) }
  end

  it "preserves insertion-order precedence across route shapes" do
    router = build do
      add "/get/domains/:id", :a_domain
      add "/get/domains/mine", :my_domains
      add "/get/*path", :fallback
    end

    expect_same_best_match(router, "/get/domains/mine")
    expect_same_best_match(router, "/get/domains/32")
    expect_same_best_match(router, "/get/other/path")
  end

  it "matches optional and overlapping constrained routes" do
    router = build do
      add "/get/posts(/:id)", :optional_post
      add "/get/posts/:id/edit", :edit_post
      add "/get/items/:id", :generic_item
      add "/get/items/:page", :numeric_item, {page: /\A\d+\z/}
      add "/get/items/:slug", :slug_item, {slug: /\A\w+-\w+\z/}
    end

    %w(
      /get/posts
      /get/posts/7
      /get/posts/7/edit
      /get/items/123
      /get/items/hello-world
      /get/items/plain
    ).each { |path| expect_same_best_match(router, path) }
  end
end
