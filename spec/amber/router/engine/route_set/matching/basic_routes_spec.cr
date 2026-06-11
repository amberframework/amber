require "../../spec_helper"

describe "basic routes" do
  it "resolves a root route" do
    build.find("/get").payload?.should eq :root
  end

  it "doesnt care about leading slashes" do
    build.find("get").payload?.should eq :root
    build.find("/get").payload?.should eq :root
  end

  it "resolves nested urls" do
    router = build do
      add "/get/books/23/chapters", :book_chapters
    end

    result = router.find "/get/books/23/chapters"
    result.payload?.should eq :book_chapters
  end

  it "returns a nil payload? for not found urls" do
    router = build
    result = router.find "/get/books/23/pages"
    result.found?.should eq false
    result.payload?.should eq nil
  end

  it "routes many segments" do
    router = build do
      add "/get/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z", :alphabet
      add "/get/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/f", :almost_alphabet
    end

    result = router.find "/get/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z"
    result.payload?.should eq :alphabet
  end
end
