require "../../spec_helper"

describe "routes with variables" do
  it "routes correctly with variables" do
    router = build do
      add "/get/users/:id", :user_path
    end

    result = router.find "/get/users/3"
    result.payload?.should eq :user_path
  end

  it "routes many variables" do
    router = build do
      add "/get/var/:b/:c/:d/:e/:f/:g/:h/:i/:j/:k/:l/:m/:n/:o/:p/:q/:r/:s/:t/:u/:v/:w/:x/:y/:z", :variable_alphabet
    end

    result = router.find "/get/var/2/3/4/5/6/7/8/9/0/1/2/3/4/5/6/7/8/9/0/1/2/3/4/5/6"
    result.payload?.should eq :variable_alphabet
  end

  it "correctly selects routes" do
    router = build do
      add "/get/users/:id", :users
      add "/get/users/:id/books", :users_books
      add "/get/books/:id", :books
      add "/get/books/:id/chapters", :book_chapters
      add "/get/books/:id/authors", :book_authors
      add "/get/books/:id/pictures", :book_pictures
    end

    router.find("/get/").payload?.should eq :root
    router.find("/get/users/3").payload?.should eq :users
    router.find("/get/users/3/books").payload?.should eq :users_books
    router.find("/get/books/3").payload?.should eq :books
    router.find("/get/books/3/chapters").payload?.should eq :book_chapters
    router.find("/get/books/3/authors").payload?.should eq :book_authors
    router.find("/get/books/3/pictures").payload?.should eq :book_pictures
  end

  it "routes with constraints" do
    router = build do
      # With symbol hash
      add "/get/posts/:page", :user_path, {:page => :numeric}

      # With string hash
      add "/get/test/:id", :user_path, {"id" => Amber::Router::ParamConstraints::Custom.new("foo_digit") { |segment| segment.size == 5 && segment.starts_with?("foo_") && segment[4].ascii_number? }}

      # with named tuple
      add "/get/time/:id", :user_path, {id: Amber::Router::ParamConstraints::Custom.new("clock") { |segment| segment.split(':').all? { |part| part.size == 1 && part[0].ascii_number? } && segment.count(':') == 2 }}
    end

    router.find("/get/posts/1").found?.should be_true
    router.find("/get/posts/foo").found?.should be_false

    router.find("/get/time/foo").found?.should be_false
    router.find("/get/time/1:2:3").found?.should be_true

    router.find("/get/test/foo_7").found?.should be_true
    router.find("/get/test/foo_").found?.should be_false
  end
end
