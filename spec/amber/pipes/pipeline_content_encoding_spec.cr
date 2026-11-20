require "../../spec_helper"

# A request body that records whether anything read from it.
private class ReadRecordingBody < IO
  getter? was_read = false

  def read(slice : Bytes) : Int32
    @was_read = true
    0
  end

  def write(slice : Bytes) : Nil
    raise IO::Error.new("ReadRecordingBody is read-only")
  end
end

private def build_encoded_request(content_encoding : String | Array(String), body : IO, path : String = "/hello") : HTTP::Request
  headers = HTTP::Headers.new
  headers.add("Content-Encoding", content_encoding)
  headers["Content-Type"] = "application/x-www-form-urlencoded"
  HTTP::Request.new("POST", path, headers, body)
end

private def with_encoded_request_bodies_accepted(&)
  Amber.settings.params.accepts_encoded_request_bodies = true
  begin
    yield
  ensure
    Amber.settings.params.accepts_encoded_request_bodies = false
  end
end

module Amber::Pipe
  describe Pipeline do
    describe "a request body with a Content-Encoding" do
      pipeline = Pipeline.new
      before_each do
        Amber::Server.router.draw :web do
          resources "/hello", HelloController
        end
        pipeline = Pipeline.new
        pipeline.build :web { }
        pipeline.prepare_pipelines
      end

      it "is answered 415 before any handler reads the body" do
        body = ReadRecordingBody.new
        response = create_request_and_return_io(pipeline, build_encoded_request("gzip", body))

        response.status_code.should eq 415
        response.headers["Accept-Encoding"].should eq "identity"
        response.headers["Connection"].should eq "close"
        response.body.should eq "415 Unsupported Media Type\n"
        body.was_read?.should be_false
      end

      it "is answered 415 before routing, even on a path with no route" do
        body = ReadRecordingBody.new
        response = create_request_and_return_io(pipeline, build_encoded_request("deflate", body, "/no/such/route"))

        response.status_code.should eq 415
        body.was_read?.should be_false
      end

      it "is answered 415 when any listed coding is not identity" do
        ["identity, gzip", "x-gzip", "br", "GZIP"].each do |content_encoding|
          response = create_request_and_return_io(pipeline, build_encoded_request(content_encoding, ReadRecordingBody.new))
          response.status_code.should eq 415
        end

        response = create_request_and_return_io(pipeline, build_encoded_request(["identity", "gzip"], ReadRecordingBody.new))
        response.status_code.should eq 415
      end

      it "reaches the action when every coding is identity" do
        ["identity", "Identity", " identity , ", ""].each do |content_encoding|
          response = create_request_and_return_io(pipeline, build_encoded_request(content_encoding, IO::Memory.new("")))
          response.status_code.should eq 200
          response.body.should eq "Create"
        end
      end

      it "reaches the action when the application accepts encoded request bodies" do
        with_encoded_request_bodies_accepted do
          response = create_request_and_return_io(pipeline, build_encoded_request("gzip", IO::Memory.new("")))

          response.status_code.should eq 200
          response.body.should eq "Create"
        end
      end
    end

    describe ".content_encoded?" do
      it "is false without a Content-Encoding header" do
        Pipeline.content_encoded?(HTTP::Request.new("POST", "/")).should be_false
      end

      it "is true for a coding other than identity" do
        request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Encoding" => "gzip"})
        Pipeline.content_encoded?(request).should be_true
      end
    end
  end
end
