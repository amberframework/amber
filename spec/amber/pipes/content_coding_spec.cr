require "../../spec_helper"

private def headers(value : String) : HTTP::Headers
  HTTP::Headers{"Accept-Encoding" => value}
end

module Amber::Pipe
  describe ContentCoding do
    describe ".quality" do
      it "reads a coding's own entry, then *, and counts a bad q as 0" do
        ContentCoding.quality(headers("br;q=0.4, *;q=0.9"), "br").should eq 0.4
        ContentCoding.quality(headers("br;q=0.4, *;q=0.9"), "gzip").should eq 0.9
        ContentCoding.quality(headers("x-gzip"), "gzip").should eq 1.0
        ContentCoding.quality(headers("BR;Q=0.5"), "br").should eq 0.5
        ContentCoding.quality(headers("br;q=abc"), "br").should eq 0.0
        ContentCoding.quality(headers("gzip"), "br").should eq 0.0
      end

      it "accepts identity unless it or * is given q=0" do
        ContentCoding.quality(headers("gzip"), "identity").should eq 1.0
        ContentCoding.quality(headers("identity;q=0"), "identity").should eq 0.0
        ContentCoding.quality(headers("*;q=0"), "identity").should eq 0.0
      end

      it "accepts every coding when the request has no Accept-Encoding" do
        ContentCoding.quality(HTTP::Headers.new, "br").should eq 1.0
      end
    end

    describe ".choose" do
      it "picks the highest quality, the server's earlier coding on a tie" do
        ContentCoding.choose(headers("gzip, br"), ["br", "gzip"]).should eq "br"
        ContentCoding.choose(headers("gzip, br;q=0.9"), ["br", "gzip"]).should eq "gzip"
        ContentCoding.choose(headers("br;q=0, gzip;q=0"), ["br", "gzip"]).should be_nil
      end

      it "chooses nothing for a request with no Accept-Encoding" do
        ContentCoding.choose(HTTP::Headers.new, ["br", "gzip"]).should be_nil
      end
    end
  end
end
