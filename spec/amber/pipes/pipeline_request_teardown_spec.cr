require "../../spec_helper"

private def build_upload_request(path : String = "/") : HTTP::Request
  headers = HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=fhhRFLCazlkA0dX; charset=UTF-8"}
  multipart_body = ::File.read(::File.expand_path("spec/support/sample/multipart.txt")).gsub("\n", "\r\n")
  HTTP::Request.new("POST", path, headers, multipart_body)
end

module Amber::Pipe
  describe Pipeline do
    describe "#call" do
      it "deletes upload tempfiles when the request finishes" do
        Amber::Server.router.draw :web do
          post "/teardown/uploads", HelloController, :create
        end
        pipeline = Pipeline.new
        pipeline.build :web { }
        pipeline.prepare_pipelines
        context = create_context(build_upload_request("/teardown/uploads"))
        upload_path = context.params.files["picture"].file.path

        pipeline.call(context)

        ::File.exists?(upload_path).should be_false
      end
    end
  end
end

module Amber::Router
  describe Params do
    it "leaves a multipart request body readable after parsing the files" do
      request = build_upload_request
      original_body = request.body.as(IO).gets_to_end
      request.body = original_body

      request.params.files["picture"].filename.should eq "index.html"

      request.body.as(IO).gets_to_end.should eq original_body
    end
  end
end
