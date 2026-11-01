require "../../../spec_helper"

private def build_multipart_request : HTTP::Request
  headers = HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=fhhRFLCazlkA0dX; charset=UTF-8"}
  multipart_body = ::File.read(::File.expand_path("spec/support/sample/multipart.txt")).gsub("\n", "\r\n")
  # Send Content-Length as a client does; the spool decision reads it.
  headers["Content-Length"] = multipart_body.bytesize.to_s
  HTTP::Request.new("POST", "/", headers, multipart_body)
end

private def restore_limited(request : HTTP::Request, limit : Int64) : HTTP::Request
  limits = Amber::Configuration::ParamsConfig.new
  limits.max_multipart_restore_bytes = limit
  request.param_budget = Amber::Router::Parsers::ParamBudget.new(limits)
  request
end

module Amber::Router::Parsers
  describe Multipart do
    describe ".parse" do
      it "leaves the request body readable when it is within the restore limit" do
        request = build_multipart_request
        original_body = request.body.as(IO).gets_to_end
        request.body = IO::Memory.new(original_body)

        params, files, body_copy = Multipart.parse(request)

        params["title"].should eq "title field"
        files["picture"].filename.should eq "index.html"
        request.body.as(IO).gets_to_end.should eq original_body
        if body_copy
          ::File.dirname(body_copy.path).should eq Amber::Router::File.upload_directory
          Amber::Router::File.discard(body_copy)
        else
          fail "the body was not copied"
        end
        files.each_value(&.delete_tempfile)
      end

      it "leaves the body drained and copies nothing above max_multipart_restore_bytes" do
        request = restore_limited(build_multipart_request, 16_i64)

        params, files, body_copy = Multipart.parse(request)

        params["title"].should eq "title field"
        body_copy.should be_nil
        request.body.as(IO).gets_to_end.should be_empty
        files.each_value(&.delete_tempfile)
      end

      it "copies nothing when max_multipart_restore_bytes is 0" do
        request = restore_limited(build_multipart_request, 0_i64)

        _params, files, body_copy = Multipart.parse(request)

        body_copy.should be_nil
        files.each_value(&.delete_tempfile)
      end

      it "copies nothing when the request has no Content-Length" do
        request = build_multipart_request
        request.headers.delete("Content-Length")

        _params, files, body_copy = Multipart.parse(request)

        body_copy.should be_nil
        files.each_value(&.delete_tempfile)
      end

      it "parses a body longer than its Content-Length from the copy and the rest of the body" do
        request = build_multipart_request
        full_body = request.body.as(IO).gets_to_end
        request.body = IO::Memory.new(full_body)
        request.headers["Content-Length"] = "10"

        params, files, body_copy = Multipart.parse(request)

        params["title"].should eq "title field"
        files["picture"].filename.should eq "index.html"
        request.body.as(IO).gets_to_end.should be_empty
        if body_copy
          ::File.exists?(body_copy.path).should be_true
          Amber::Router::File.discard(body_copy)
          ::File.exists?(body_copy.path).should be_false
        else
          fail "the first bytes were not copied"
        end
        files.each_value(&.delete_tempfile)
      end

      it "copies nothing for a Content-Length of 0" do
        request = build_multipart_request
        full_body = request.body.as(IO).gets_to_end
        request.body = IO::Memory.new(full_body)
        request.headers["Content-Length"] = "0"

        params, files, body_copy = Multipart.parse(request)

        params["title"].should eq "title field"
        body_copy.should be_nil
        files.each_value(&.delete_tempfile)
      end

      it "copies the body into the private upload directory and deletes the copy on a rejected parse" do
        limits = Amber::Configuration::ParamsConfig.new
        limits.max_file_bytes = 4_i64
        request = build_multipart_request
        request.param_budget = Amber::Router::Parsers::ParamBudget.new(limits)
        list_of_copies_before = Dir.glob(::File.join(Amber::Router::File.upload_directory, "amber-multipart-body*"))

        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_file_bytes/) do
          Multipart.parse(request)
        end

        Dir.glob(::File.join(Amber::Router::File.upload_directory, "amber-multipart-body*")).should eq list_of_copies_before
      end
    end
  end
end

module Amber::Router
  describe Params do
    describe "#delete_uploaded_files" do
      it "deletes the uploaded file tempfiles and the body copy" do
        request = build_multipart_request
        upload_path = request.params.files["picture"].path
        body_copy_path = request.body.as(::File).path
        ::File.exists?(upload_path).should be_true
        ::File.exists?(body_copy_path).should be_true

        request.delete_uploaded_files

        ::File.exists?(upload_path).should be_false
        ::File.exists?(body_copy_path).should be_false
        request.params.files.should be_empty
      end

      it "does not parse a request whose params were never read" do
        request = build_multipart_request

        request.delete_uploaded_files

        request.body.as(IO).gets_to_end.should_not be_empty
      end
    end
  end
end
