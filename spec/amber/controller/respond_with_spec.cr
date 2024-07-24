require "../../spec_helper"

module Amber::Controller
  describe Base do
    describe "#respond_with" do
      request = HTTP::Request.new("GET", "")
      request.headers["Accept"] = ""
      context = create_context(request)

      describe "#string input" do
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
          context.response.headers["Content-Type"].should eq "application/json; charset=utf-8"
          context.response.status_code.should eq 200
        end

        it "responds with json having */* at end" do
          expected_result = %({"type":"json","name":"Amberator"})
          context.request.headers["Accept"] = "application/json,*/*"
          ResponsesController.new(context).index.should eq expected_result
          context.response.headers["Content-Type"].should eq "application/json; charset=utf-8"
          context.response.status_code.should eq 200
        end

        it "responds with javascript" do
          expected_result = %(console.log('Everyone <3 Amber'))
          context.request.headers["Accept"] = "text/javascript"
          ResponsesController.new(context).index.should eq expected_result
          context.response.headers["Content-Type"].should eq "text/javascript"
          context.response.status_code.should eq 200
        end

        it "responds with javascript having */* at end" do
          expected_result = %(console.log('Everyone <3 Amber'))
          context.request.headers["Accept"] = "text/javascript,*/*"
          ResponsesController.new(context).index.should eq expected_result
          context.response.headers["Content-Type"].should eq "text/javascript"
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
          context.response.headers["Content-Type"].should eq "application/json; charset=utf-8"
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
          context.response.status_code = 200
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
          context.response.headers["Content-Type"].should eq "application/json; charset=utf-8"
          context.response.status_code.should eq 200
        end

        it "responds html as default with invalid extension but having */* at end" do
          expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
          context.request.headers["Accept"] = "unsupported/extension,*/*"
          ResponsesController.new(context).index.should eq expected_result
          context.response.headers["Content-Type"].should eq "text/html"
          context.response.status_code.should eq 200
        end

        it "responds with 403 custom status_code" do
          expected_result = %({"type":"json","error":"Unauthorized"})
          context.request.headers["Accept"] = "application/json"
          ResponsesController.new(context).custom_status_code.should eq expected_result
          context.response.headers["Content-Type"].should eq "application/json; charset=utf-8"
          context.response.status_code.should eq 403
        end
      end

      describe "#proc input" do
        it "responds with html from a proc" do
          context.response.status_code = 200
          expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
          context.request.headers["Accept"] = "text/html"
          ResponsesController.new(context).proc_html.should eq expected_result
          context.response.headers["Content-Type"].should eq "text/html"
          context.response.status_code.should eq 200
        end

        it "redirects from a proc" do
          context.response.status_code = 200
          expected_result = "302"
          context.request.headers["Accept"] = "text/html"
          ResponsesController.new(context).proc_redirect.should eq expected_result
          context.response.headers["Location"].should eq "/some_path"
          context.response.status_code.should eq 302
        end

        it "redirects with flash from a proc" do
          context.response.status_code = 200
          expected_result = "302"
          context.request.headers["Accept"] = "text/html"
          ResponsesController.new(context).proc_redirect_flash.should eq expected_result
          context.flash["success"].should eq "amber is the bizness"
          context.response.headers["Location"].should eq "/some_path"
          context.response.status_code.should eq 302
        end

        it "redirects with a status code from a proc" do
          context.response.status_code = 200
          expected_result = "301"
          context.request.headers["Accept"] = "text/html"
          ResponsesController.new(context).proc_perm_redirect.should eq expected_result
          context.response.headers["Location"].should eq "/some_path"
          context.response.status_code.should eq 301
        end
      end
    end
  end
end
