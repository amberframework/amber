require "./spec_helper"

describe ExceptionPage do
  it "renders an error page with debugging information" do
    server = HTTP::Server.new([TestHandler.new])
    addr = server.bind_unused_port

    spawn { server.listen }

    begin
      response = HTTP::Client.get("http://#{addr}/")
      body = response.body

      body.should contain("Something went very wrong")
      body.should contain("test_handler.cr")
    ensure
      server.close
    end
  end

  it "renders a multiline exception page" do
    server = HTTP::Server.new([TestHandler.new])
    addr = server.bind_unused_port

    spawn { server.listen }

    begin
      response = HTTP::Client.get("http://#{addr}/multiline-exception")
      body = response.body

      body.should contain("Something went very wrong")
      body.should contain("But wait, there&#39;s more!")
    ensure
      server.close
    end
  end

  it "allows instantiating one manually" do
    MyApp::ExceptionPage.new Exception.new("Oh noes"), "SEARCH", "/users", :im_a_teapot
  end
end
