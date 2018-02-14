require "../../../spec_helper"

module Amber::Router
  describe Params do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "multipart/form-data; boundary=fhhRFLCazlkA0dX; charset=UTF-8"
    multipart_content = ::File.read(::File.expand_path("spec/support/sample/multipart.txt"))
    multipart_body = multipart_content.gsub("\n", "\r\n")
    request = HTTP::Request.new("GET", "/?test=test&test=test2&#{HTTP::Request::METHOD}=put", headers, multipart_body)
    params = Params.new(request)

    describe "#[]" do
      it "return query string param" do
        params["test"].should eq "test"
      end

      it "returns form data params" do
        params["title"].should eq "title field"
        params["_csrf"].should eq "PcCFp4oKJ1g-hZ-P7-phg0alC51pz7Pl12r0ZOncgxI"
      end

      it "raises error for non existent param" do
        expect_raises Amber::Exceptions::Validator::InvalidParam do
          params["invalid"]
        end
      end
    end

    describe "#fetch_all" do
      it "returns an array of params" do
        params.fetch_all("test").should eq %w(test test2)
      end
    end

    describe "#files" do
      it "returns parsed multipart files" do
        params.files["picture"].filename.should eq "index.html"
      end
    end

    describe "#key?" do
      it "returns nil for non-existent key" do
        params.key?("invalid").should be_nil
      end

      it "retuns value for existing key" do
        params.key?("test").should eq "test"
      end
    end

    describe "#override_method?" do
      it "returns override method value" do
        params.override_method?(HTTP::Request::METHOD).should eq "put"
      end

      it "returns nil for nonexistent override method" do
        params.override_method?("non-existent").should be_nil
      end
    end
  end
end
