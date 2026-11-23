require "../../spec_helper"

# Text that compresses well, long enough to fill several output buffers.
private LONG_BODY = String.build do |text|
  2_000.times { |line_number| text << "<li class=\"post\">Post number " << line_number << " of the long page</li>\n" }
end

# Random bytes, which DEFLATE cannot shrink, so the output spans many buffers.
private RANDOM_BODY = Random.new(42).random_bytes(70_000)

private DECODE_LIMITS = Amber::Mica::Deflate::DecodeLimits::TRUSTED_ASSET

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

private def request_accepting(encodings : String?, headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Request
  headers["Accept-Encoding"] = encodings if encodings
  HTTP::Request.new("GET", "/", headers)
end

private def gunzip(body : Bytes) : Bytes
  Amber::Mica::Gzip.decode(body, limits: DECODE_LIMITS, timeout: nil)
end

# Decodes a `Content-Encoding: deflate` body in the framing the compiler's
# `HTTP::CompressHandler` uses.
private def inflate(body : Bytes) : Bytes
  if Amber::Pipe::Compression::CompressedOutput::ZLIB_FRAMED_DEFLATE
    Amber::Mica::Zlib.decode(body, limits: DECODE_LIMITS, timeout: nil)
  else
    Amber::Mica::Deflate.decode(body, limits: DECODE_LIMITS, timeout: nil)
  end
end

private def unbrotli(body : Bytes) : Bytes
  Amber::Mica::Brotli.decode(body, limits: Amber::Mica::Brotli::DecodeLimits::TRUSTED_ASSET, timeout: nil)
end

private def bytes_of(chunks : Array(String | Bytes)) : Bytes
  joined = IO::Memory.new
  chunks.each { |chunk| joined.write(chunk.to_slice) }
  joined.to_slice
end

private CASES = {
  "one write of 1,024 bytes" => {[LONG_BODY[0, 1_024]] of String | Bytes, false},
  "one long write"           => {[LONG_BODY] of String | Bytes, false},
  "many writes"              => {LONG_BODY.lines(chomp: false).map(&.as(String | Bytes)), false},
  "random bytes"             => {[RANDOM_BODY.as(String | Bytes)], false},
  "a flush after the first"  => {[LONG_BODY, LONG_BODY].map(&.as(String | Bytes)), true},
}

module Amber::Pipe
  describe Compression do
    describe "#call" do
      CASES.each do |name, (chunks, flushes)|
        it "writes a gzip stream that decodes to the body for #{name}" do
          served = serve(Compression.new, request_accepting("gzip"), chunks, flushes)

          served.headers["Content-Encoding"].should eq "gzip"
          gunzip(served.body).should eq bytes_of(chunks)
        end

        it "writes a Brotli stream that decodes to the body for #{name}" do
          served = serve(Compression.new, request_accepting("br"), chunks, flushes)

          served.headers["Content-Encoding"].should eq "br"
          unbrotli(served.body).should eq bytes_of(chunks)
        end

        it "writes a deflate stream that decodes to the body for #{name}" do
          served = serve(Compression.new, request_accepting("deflate"), chunks, flushes)

          served.headers["Content-Encoding"].should eq "deflate"
          inflate(served.body).should eq bytes_of(chunks)
        end
      end

      {% unless flag?(:without_zlib) %}
        CASES.each do |name, (chunks, flushes)|
          it "writes streams zlib decodes, at most 1% larger than HTTP::CompressHandler's, for #{name}" do
            gzip = serve(Compression.new, request_accepting("gzip"), chunks, flushes)
            deflate = IO::Memory.new(serve(Compression.new, request_accepting("deflate"), chunks, flushes).body)
            expected = serve(HTTP::CompressHandler.new, request_accepting("gzip"), chunks, flushes)

            Compress::Gzip::Reader.open(IO::Memory.new(gzip.body), &.getb_to_end).should eq bytes_of(chunks)
            decoded = if Compression::CompressedOutput::ZLIB_FRAMED_DEFLATE
                        Compress::Zlib::Reader.open(deflate, &.getb_to_end)
                      else
                        Compress::Deflate::Reader.open(deflate, &.getb_to_end)
                      end
            decoded.should eq bytes_of(chunks)
            gzip.body.size.should be <= expected.body.size + expected.body.size // 100 + 16
          end
        end
      {% end %}

      it "sends a body that is never written without a content coding" do
        served = serve(Compression.new, request_accepting("gzip"), ["".as(String | Bytes)])

        served.headers["Content-Encoding"]?.should be_nil
        served.body.should be_empty
      end

      it "prefers Brotli on a tie, reports Vary and drops Content-Length" do
        served = serve(Compression.new, request_accepting("gzip, deflate, br"), [LONG_BODY] of String | Bytes)

        served.headers["Content-Encoding"].should eq "br"
        served.headers["Vary"].should eq "Accept-Encoding"
        served.headers["Content-Length"]?.should be_nil
        String.new(unbrotli(served.body)).should eq LONG_BODY
      end

      it "follows the client's q-values over the server's preference" do
        {
          "br;q=0.5, gzip"          => "gzip",
          "br;q=0, gzip;q=0.1"      => "gzip",
          "gzip;q=0, deflate;q=0.5" => "deflate",
          "br;q=0, gzip;q=0, *;q=1" => "deflate",
          "*"                       => "br",
          "gzip;q=0, deflate;q=0"   => nil,
          "identity"                => nil,
        }.each do |accept_encoding, expected|
          served = serve(Compression.new, request_accepting(accept_encoding), [LONG_BODY] of String | Bytes)
          served.headers["Content-Encoding"]?.should eq expected
        end
      end

      it "offers gzip and deflate only when Brotli is switched off" do
        served = serve(Compression.new(brotli_quality: nil), request_accepting("gzip, deflate, br"), [LONG_BODY] of String | Bytes)

        served.headers["Content-Encoding"].should eq "gzip"
        served.headers["Vary"].should eq "Accept-Encoding"
        served.headers["Content-Length"]?.should be_nil
        String.new(gunzip(served.body)).should eq LONG_BODY
      end

      it "rejects a Brotli quality outside 0..11" do
        expect_raises(ArgumentError, /Brotli quality/) { Compression.new(brotli_quality: 12) }
        expect_raises(ArgumentError, /Brotli quality/) { Compression.new(brotli_quality: -1) }
      end

      it "writes the same bytes for the same body: a gzip header with no time stamp" do
        first = serve(Compression.new, request_accepting("gzip"), [LONG_BODY] of String | Bytes)
        second = serve(Compression.new, request_accepting("gzip"), [LONG_BODY] of String | Bytes)

        first.body.should eq second.body
        first.body[0, 10].should eq Bytes[0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]
      end

      it "lets the client decode everything written before a flush" do
        pipe = Compression.new
        io = IO::Memory.new
        bytes_at_flush = 0
        pipe.next = ->(context : HTTP::Server::Context) do
          context.response.print LONG_BODY
          context.response.flush
          bytes_at_flush = io.pos.to_i
          context.response.print "the rest"
          nil
        end
        response = HTTP::Server::Response.new(io)
        pipe.call(HTTP::Server::Context.new(request_accepting("gzip"), response))
        response.close

        flushed = IO::Memory.new
        flushed.write(io.to_slice[0, bytes_at_flush])
        flushed << "0\r\n\r\n"
        body = HTTP::Client::Response.from_io(flushed.rewind, decompress: false).body.to_slice
        reader = Amber::Mica::Gzip::Reader.new(IO::Memory.new(body), limits: DECODE_LIMITS, timeout: nil)
        decoded = Bytes.new(LONG_BODY.bytesize)
        reader.read_fully(decoded)
        String.new(decoded).should eq LONG_BODY
      end

      {0, 1, 4, 9}.each do |level|
        it "writes valid gzip and deflate streams at level #{level}" do
          pipe = Compression.new(level: level)
          gzip = serve(pipe, request_accepting("gzip"), [LONG_BODY] of String | Bytes)
          deflate = serve(pipe, request_accepting("deflate"), [LONG_BODY] of String | Bytes)

          String.new(gunzip(gzip.body)).should eq LONG_BODY
          String.new(inflate(deflate.body)).should eq LONG_BODY
        end
      end

      it "compresses harder at a higher level" do
        stored = serve(Compression.new(level: 0), request_accepting("gzip"), [LONG_BODY] of String | Bytes)
        fastest = serve(Compression.new(level: 1), request_accepting("gzip"), [LONG_BODY] of String | Bytes)
        smallest = serve(Compression.new(level: 9), request_accepting("gzip"), [LONG_BODY] of String | Bytes)

        stored.body.size.should be > LONG_BODY.bytesize
        fastest.body.size.should be < LONG_BODY.bytesize // 4
        smallest.body.size.should be <= fastest.body.size
      end

      it "prefers gzip when the client accepts both" do
        serve(Compression.new, request_accepting("deflate, gzip"), [LONG_BODY] of String | Bytes)
          .headers["Content-Encoding"].should eq "gzip"
      end

      it "sends a body shorter than 1,024 bytes without a content coding" do
        {[LONG_BODY[0, 1_023]], LONG_BODY[0, 1_023].chars.map(&.to_s)}.each do |chunks|
          served = serve(Compression.new, request_accepting("br, gzip"), chunks.map(&.as(String | Bytes)))

          served.headers["Content-Encoding"]?.should be_nil
          served.headers["Vary"].should eq "Accept-Encoding"
          String.new(served.body).should eq LONG_BODY[0, 1_023]
        end
      end

      it "compresses once small writes add up to 1,024 bytes" do
        chunks = LONG_BODY[0, 1_024].chars.map(&.to_s.as(String | Bytes))
        served = serve(Compression.new, request_accepting("br"), chunks)

        served.headers["Content-Encoding"].should eq "br"
        String.new(unbrotli(served.body)).should eq LONG_BODY[0, 1_024]
      end

      it "decides the coding at a flush, however short the body so far" do
        chunks = ["<p>Hello</p>", LONG_BODY[0, 10]].map(&.as(String | Bytes))
        served = serve(Compression.new, request_accepting("gzip"), chunks, flushes: true)

        served.headers["Content-Encoding"].should eq "gzip"
        gunzip(served.body).should eq bytes_of(chunks)
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

      it "keeps the compressor's tables outside the collected heap" do
        chunks = [LONG_BODY] of String | Bytes
        request = request_accepting("gzip")
        pipe = Compression.new
        serve(pipe, request, chunks)

        before = GC.stats.total_bytes
        20.times { serve(pipe, request, chunks) }
        bytes_per_response = (GC.stats.total_bytes - before) // 20

        # The response and its parsing cost a multiple of the compressed
        # body; the compressor's 270 KB of tables would dwarf that.
        bytes_per_response.should be < 100_000
      end
    end

    describe "#initialize" do
      it "refuses a level outside 0 to 9 and -1" do
        expect_raises(ArgumentError, "Compression level must be in -1..9, got 10") { Compression.new(level: 10) }
        expect_raises(ArgumentError, "Compression level must be in -1..9, got -2") { Compression.new(level: -2) }
      end

      it "compresses at level 6 by default and when given -1" do
        Compression.new.level.should eq 6
        Compression.new(level: -1).level.should eq 6
        Compression.new(level: 3).level.should eq 3
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
