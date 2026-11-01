require "../../../spec_helper"

private def build_multipart_request : HTTP::Request
  headers = HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=fhhRFLCazlkA0dX; charset=UTF-8"}
  multipart_body = ::File.read(::File.expand_path("spec/support/sample/multipart.txt")).gsub("\n", "\r\n")
  # Send Content-Length as a client does; the spool decision reads it.
  headers["Content-Length"] = multipart_body.bytesize.to_s
  HTTP::Request.new("POST", "/", headers, multipart_body)
end

private def with_multipart_body_restore_limit(limit : Int64, &)
  original_limit = Amber.settings.multipart_body_restore_limit
  Amber.settings.multipart_body_restore_limit = limit
  begin
    yield
  ensure
    Amber.settings.multipart_body_restore_limit = original_limit
  end
end

module Amber::Router::Parsers
  describe Multipart do
    describe ".parse" do
      it "leaves the request body readable when it is within the restore limit" do
        request = build_multipart_request
        original_body = request.body.as(IO).gets_to_end
        request.body = IO::Memory.new(original_body)

        params, files, spool = Multipart.parse(request)

        params["title"].should eq "title field"
        files["picture"].filename.should eq "index.html"
        request.body.as(IO).gets_to_end.should eq original_body
        spool.should_not be_nil
        request.cleanup_uploads
      end

      it "leaves the body drained and spools nothing above the restore limit" do
        with_multipart_body_restore_limit(16_i64) do
          request = build_multipart_request

          params, _files, spool = Multipart.parse(request)

          params["title"].should eq "title field"
          spool.should be_nil
        end
      end
    end
  end
end

module Amber::Router
  describe Params do
    describe "#cleanup_uploads" do
      it "deletes the uploaded file tempfiles and the body spool" do
        request = build_multipart_request
        upload_path = request.params.files["picture"].file.path
        ::File.exists?(upload_path).should be_true

        request.cleanup_uploads

        ::File.exists?(upload_path).should be_false
        request.params.files.should be_empty
      end

      it "does not parse a request whose params were never read" do
        request = build_multipart_request

        request.cleanup_uploads

        request.body.as(IO).gets_to_end.should_not be_empty
      end
    end
  end
end
