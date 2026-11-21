require "../../spec_helper"

{% unless flag?(:without_zlib) %}
  # Text that compresses well, long enough to fill several zlib output buffers.
  private LONG_BODY = String.build do |text|
    2_000.times { |line_number| text << "<li class=\"post\">Post number " << line_number << " of the long page</li>\n" }
  end

  # Random bytes, which zlib cannot shrink, so the output spans many buffers.
  private RANDOM_BODY = Random.new(42).random_bytes(70_000)

  private record ServedResponse, headers : HTTP::Headers, body : Bytes

  # Runs *handler* in front of an action that writes each of *chunks*,
  # flushing after the first chunk when *flushes* is true, and returns the
  # raw response.
  private def serve(handler : HTTP::Handler, request : HTTP::Request, chunks : Array(String | Bytes),
                    flushes : Bool = false) : ServedResponse
    handler.next = ->(context : HTTP::Server::Context) do
      chunks.each_with_index do |chunk, index|
        context.response.write(chunk.to_slice)
        context.response.flush if flushes && index == 0
      end
      nil
    end
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    handler.call(HTTP::Server::Context.new(request, response))
    response.close
    io.rewind
    client_response = HTTP::Client::Response.from_io(io, decompress: false)
    ServedResponse.new(client_response.headers, client_response.body.to_slice)
  end

  # The gzip header's modification time is the clock at the first write, so
  # two runs compare equal once it is blanked.
  private def without_gzip_time(body : Bytes) : Bytes
    copy = body.dup
    (4...8).each { |index| copy[index] = 0_u8 } if copy.size >= 8
    copy
  end

  private def request_accepting(encodings : String?, headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Request
    headers["Accept-Encoding"] = encodings if encodings
    HTTP::Request.new("GET", "/", headers)
  end

  private CASES = {
    "one small write"         => {[%(<p>Hello</p>)] of String | Bytes, false},
    "one long write"          => {[LONG_BODY] of String | Bytes, false},
    "many writes"             => {LONG_BODY.lines.map(&.as(String | Bytes)), false},
    "an empty write"          => {["".as(String | Bytes)], false},
    "random bytes"            => {[RANDOM_BODY.as(String | Bytes)], false},
    "a flush after the first" => {[LONG_BODY, LONG_BODY].map(&.as(String | Bytes)), true},
  }

  module Amber::Pipe
    describe Compression do
      describe "#call" do
        {"gzip", "deflate"}.each do |coding|
          CASES.each do |name, (chunks, flushes)|
            it "writes the bytes HTTP::CompressHandler writes for #{name}, as #{coding}" do
              request = request_accepting(coding)
              expected = serve(HTTP::CompressHandler.new, request, chunks, flushes)
              actual = serve(Compression.new, request, chunks, flushes)

              actual.headers["Content-Encoding"]?.should eq expected.headers["Content-Encoding"]?
              if coding == "gzip"
                without_gzip_time(actual.body).should eq without_gzip_time(expected.body)
              else
                actual.body.should eq expected.body
              end
            end
          end
        end

        it "round-trips through a gzip reader" do
          served = serve(Compression.new, request_accepting("gzip, deflate, br"), [LONG_BODY] of String | Bytes)

          served.headers["Content-Encoding"].should eq "gzip"
          served.headers["Vary"].should eq "Accept-Encoding"
          Compress::Gzip::Reader.open(IO::Memory.new(served.body), &.gets_to_end).should eq LONG_BODY
        end

        it "prefers gzip when the client accepts both" do
          serve(Compression.new, request_accepting("deflate, gzip"), ["hi"] of String | Bytes)
            .headers["Content-Encoding"].should eq "gzip"
        end

        it "answers uncompressed when the client accepts neither coding" do
          served = serve(Compression.new, request_accepting(nil), ["plain"] of String | Bytes)

          served.headers["Content-Encoding"]?.should be_nil
          served.headers["Vary"].should eq "Accept-Encoding"
          String.new(served.body).should eq "plain"
        end

        it "answers a range request uncompressed and without Vary" do
          request = request_accepting("gzip", HTTP::Headers{"Range" => "bytes=0-3"})
          served = serve(Compression.new, request, ["plain"] of String | Bytes)

          served.headers["Content-Encoding"]?.should be_nil
          served.headers["Vary"]?.should be_nil
          String.new(served.body).should eq "plain"
        end

        it "passes through a response that already has a Content-Encoding" do
          pipe = Compression.new
          pipe.next = ->(context : HTTP::Server::Context) do
            context.response.headers["Content-Encoding"] = "br"
            context.response.print "already encoded"
            nil
          end
          io = IO::Memory.new
          response = HTTP::Server::Response.new(io)
          pipe.call(HTTP::Server::Context.new(request_accepting("gzip, br"), response))
          response.close

          HTTP::Client::Response.from_io(io.rewind, decompress: false).body.should eq "already encoded"
        end

        it "answers uncompressed when the action flushes before writing" do
          pipe = Compression.new
          pipe.next = ->(context : HTTP::Server::Context) do
            context.response.flush
            context.response.print "after the headers"
            nil
          end
          io = IO::Memory.new
          response = HTTP::Server::Response.new(io)
          pipe.call(HTTP::Server::Context.new(request_accepting("gzip"), response))
          response.close

          client_response = HTTP::Client::Response.from_io(io.rewind, decompress: false)
          client_response.headers["Content-Encoding"]?.should be_nil
          client_response.body.should eq "after the headers"
        end

        it "returns its compressor to the pool and reuses it for the next response" do
          pipe = Compression.new
          pipe.pool.idle_count.should eq 0
          serve(pipe, request_accepting("gzip"), [LONG_BODY] of String | Bytes)
          pipe.pool.idle_count.should eq 1
          serve(pipe, request_accepting("deflate"), [LONG_BODY] of String | Bytes)
          pipe.pool.idle_count.should eq 1
        end

        it "allocates a small fraction of what HTTP::CompressHandler allocates per response" do
          chunks = [LONG_BODY] of String | Bytes
          request = request_accepting("gzip")
          stdlib = HTTP::CompressHandler.new
          pipe = Compression.new
          serve(stdlib, request, chunks)
          serve(pipe, request, chunks)

          before = GC.stats.total_bytes
          20.times { serve(stdlib, request, chunks) }
          stdlib_bytes = GC.stats.total_bytes - before

          before = GC.stats.total_bytes
          20.times { serve(pipe, request, chunks) }
          pipe_bytes = GC.stats.total_bytes - before

          # Both totals include the response and its parsing; only the
          # compressor's ~270 KB of zlib state differs.
          (stdlib_bytes - pipe_bytes).should be > 20 * 200_000
        end
      end

      describe "#initialize" do
        it "refuses a level outside zlib's range" do
          expect_raises(ArgumentError, /level/) { Compression.new(level: 10) }
        end

        it "refuses a negative idle limit" do
          expect_raises(ArgumentError, /idle_compressors/) { Compression.new(idle_compressors: -1) }
        end
      end

      describe Compression::DeflaterPool do
        it "keeps no more idle compressors than its limit" do
          pool = Compression::DeflaterPool.new(-1, 1)
          first = pool.checkout
          second = pool.checkout
          pool.checkin(first)
          pool.checkin(second)

          pool.idle_count.should eq 1
        end
      end
    end

    describe Pipeline do
      it "still refuses a compressed request body in a pipeline that compresses responses" do
        Amber::Server.router.draw :web do
          resources "/hello", HelloController
        end
        pipeline = Pipeline.new
        pipeline.build :web { plug Amber::Pipe::Compression.new }
        pipeline.prepare_pipelines

        headers = HTTP::Headers{"Content-Encoding" => "gzip", "Accept-Encoding" => "gzip",
                                "Content-Type" => "application/x-www-form-urlencoded"}
        response = create_request_and_return_io(pipeline, HTTP::Request.new("POST", "/hello", headers, IO::Memory.new("x")))

        response.status_code.should eq 415
      end
    end
  end
{% end %}
