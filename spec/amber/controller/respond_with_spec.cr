require "../../../spec_helper"

module Amber::Controller
  describe Base do
    describe "#respond_with" do
      request = HTTP::Request.new("GET", "")
      request.headers["Accept"] = ""
      context = create_context(request)

      it "respond_with html as default option" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end

      it "respond_with html as default option with */* header" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        context.request.headers["Accept"] = "*/*"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end

      it "respond_with html" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        context.request.headers["Accept"] = "text/html"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end

      it "responds with json" do
        expected_result = %({"type":"json","name":"Amberator"})
        context.request.headers["Accept"] = "application/json"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/json"
        context.response.status_code.should eq 200
      end

      it "responds with json having */* at end" do
        expected_result = %({"type":"json","name":"Amberator"})
        context.request.headers["Accept"] = "application/json,*/*"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/json"
        context.response.status_code.should eq 200
      end

      it "responds with xml" do
        expected_result = "<xml><body><h1>Sort of xml</h1></body></xml>"
        context.request.headers["Accept"] = "application/xml"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/xml"
        context.response.status_code.should eq 200
      end

      it "responds with text" do
        expected_result = "Hello I'm text!"
        context.request.headers["Accept"] = "text/plain"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/plain"
        context.response.status_code.should eq 200
      end

      it "responds with json for path.json" do
        expected_result = %({"type":"json","name":"Amberator"})
        context.request.path = "/response/1.json"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/json"
        context.response.status_code.should eq 200
      end

      it "responds with xml for path.xml" do
        expected_result = "<xml><body><h1>Sort of xml</h1></body></xml>"
        context.request.path = "/response/1.xml"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/xml"
        context.response.status_code.should eq 200
      end

      it "responds with text for path.txt" do
        expected_result = "Hello I'm text!"
        context.request.path = "/response/1.txt"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/plain"
        context.response.status_code.should eq 200
      end

      it "responds with text for path.text" do
        expected_result = "Hello I'm text!"
        context.request.path = "/response/1.text"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/plain"
        context.response.status_code.should eq 200
      end

      it "responds with 406 for path.text when text hasn't been defined" do
        expected_result = "Response Not Acceptable."
        context.request.path = "/response/1.text"
        ResponsesController.new(context).show.should eq expected_result
        context.response.status_code.should eq 406
      end

      it "respond with default if extension is invalid and accepts isn't defined" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        context.request.path = "/response/1.texas"
        context.request.headers["Accept"] = "text/html"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end

      it "responds with or accept header request if extension is invalid" do
        expected_result = %({"type":"json","name":"Amberator"})
        context.request.headers["Accept"] = "application/json"
        context.request.path = "/response/1.texas"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/json"
        context.response.status_code.should eq 200
      end

      it "responds html as default with invalid extension but having */* at end" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        context.request.headers["Accept"] = "unsupported/extension,*/*"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end
    end
  end
end
