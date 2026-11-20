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

{% unless flag?(:without_zlib) %}
  # Counts the bytes read through it, so a spec can tell whether anything
  # pulled compressed bytes out of the connection.
  private class ByteCountingIO < IO
    getter bytes_read = 0

    def initialize(@io : IO)
    end

    def read(slice : Bytes) : Int32
      count = @io.read(slice)
      @bytes_read += count
      count
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("ByteCountingIO is read-only")
    end
  end

  private PAYLOAD = "name=compressed+payload"

  # Compresses PAYLOAD with *coding* (`gzip` or `deflate`).
  private def compress_payload(coding : String) : IO::Memory
    compressed = IO::Memory.new
    if coding == "gzip"
      Compress::Gzip::Writer.open(compressed, &.print(PAYLOAD))
    else
      Compress::Deflate::Writer.open(compressed, &.print(PAYLOAD))
    end
    compressed.rewind
  end

  # Wraps *connection* the way `HTTP::Server` wraps a *coding* body.
  private def build_decompressing_reader(coding : String, connection : IO) : IO
    if coding == "gzip"
      Compress::Gzip::Reader.new(connection)
    else
      Compress::Deflate::Reader.new(connection)
    end
  end

  # Builds the request that Crystal before 1.21.1 hands to Amber for a
  # compressed upload: the body is already a decompressing reader, and the
  # `Content-Encoding` and `Content-Length` headers are gone.
  private def build_server_inflated_request(body : IO, path : String = "/hello") : HTTP::Request
    headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    HTTP::Request.new("POST", path, headers, body)
  end
{% end %}

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

    {% unless flag?(:without_zlib) %}
      describe "a request body the server already wrapped in a decompressing reader" do
        pipeline = Pipeline.new
        before_each do
          Amber::Server.router.draw :web do
            resources "/hello", HelloController
          end
          pipeline = Pipeline.new
          pipeline.build :web { }
          pipeline.prepare_pipelines
        end

        ["gzip", "deflate"].each do |coding|
          it "is answered 415 before any byte of a #{coding} body is read" do
            connection = ByteCountingIO.new(compress_payload(coding))
            body = build_decompressing_reader(coding, connection)
            bytes_read_before = connection.bytes_read

            response = create_request_and_return_io(pipeline, build_server_inflated_request(body))

            response.status_code.should eq 415
            response.headers["Accept-Encoding"].should eq "identity"
            response.headers["Connection"].should eq "close"
            response.body.should eq "415 Unsupported Media Type\n"
            connection.bytes_read.should eq bytes_read_before
            body.gets_to_end.should eq PAYLOAD
          end
        end

        it "is answered 415 before routing, even on a path with no route" do
          connection = ByteCountingIO.new(compress_payload("gzip"))
          body = Compress::Gzip::Reader.new(connection)
          bytes_read_before = connection.bytes_read

          response = create_request_and_return_io(pipeline, build_server_inflated_request(body, "/no/such/route"))

          response.status_code.should eq 415
          connection.bytes_read.should eq bytes_read_before
        end

        it "is answered 415 for a zlib reader" do
          compressed = IO::Memory.new
          Compress::Zlib::Writer.open(compressed, &.print(PAYLOAD))
          connection = ByteCountingIO.new(compressed.rewind)
          body = Compress::Zlib::Reader.new(connection)
          bytes_read_before = connection.bytes_read

          response = create_request_and_return_io(pipeline, build_server_inflated_request(body))

          response.status_code.should eq 415
          connection.bytes_read.should eq bytes_read_before
        end

        it "reaches the action when the application accepts encoded request bodies" do
          with_encoded_request_bodies_accepted do
            body = Compress::Gzip::Reader.new(compress_payload("gzip"))
            response = create_request_and_return_io(pipeline, build_server_inflated_request(body))

            response.status_code.should eq 200
            response.body.should eq "Create"
          end
        end
      end

      describe ".body_inflated_by_server?" do
        it "is true for a body the server wrapped in a decompressing reader" do
          body = Compress::Gzip::Reader.new(compress_payload("gzip"))
          Pipeline.body_inflated_by_server?(build_server_inflated_request(body)).should be_true
        end

        it "is false for a plain body" do
          request = build_server_inflated_request(IO::Memory.new(PAYLOAD))
          Pipeline.body_inflated_by_server?(request).should be_false
        end
      end
    {% end %}

    describe ".content_encoded?" do
      it "is false without a Content-Encoding header" do
        Pipeline.content_encoded?(HTTP::Request.new("POST", "/")).should be_false
      end

      it "is true for a coding other than identity" do
        request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Encoding" => "gzip"})
        Pipeline.content_encoded?(request).should be_true
      end

      {% unless flag?(:without_zlib) %}
        it "is true for a body the server already decompresses, with no header" do
          body = Compress::Deflate::Reader.new(compress_payload("deflate"))
          Pipeline.content_encoded?(build_server_inflated_request(body)).should be_true
        end
      {% end %}
    end
  end
end
