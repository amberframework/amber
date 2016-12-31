require "./spec_helper"

describe DemoController do
  Spec.before_each do
    Demo.clear
  end

  describe DemoController::Index do
    it "renders all the demos" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      request = HTTP::Request.new("GET", "/demos")
      io, context = create_context(request)
      response = DemoController::Index.instance.call(context).as(String)
      response.should contain "test"
    end
  end

  describe DemoController::Show do
    it "renders a single demo" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      request = HTTP::Request.new("GET", "/demos/#{demo.id}")
      io, context = create_context(request)
      context.params["id"] = demo.id.to_s
      response = DemoController::Show.instance.call(context).as(String)
      response.should contain "test"
    end
  end

  describe DemoController::New do
    it "render new template" do
      request = HTTP::Request.new("GET", "/demos/new")
      io, context = create_context(request)
      response = DemoController::New.instance.call(context).as(String)
      response.should contain "New"
    end
  end

  describe DemoController::Create do
    it "" do
      request = HTTP::Request.new("POST", "/demos")
      io, context = create_context(request)
      context.params["name"] = "test"
      response = DemoController::Create.instance.call(context).as(String)
      demo = Demo.all
      demo.size.should eq 1
    end
  end

  describe DemoController::Edit do
    it "renders edit template" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      request = HTTP::Request.new("GET", "/demos/#{demo.id}/edit")
      io, context = create_context(request)
      context.params["id"] = demo.id.to_s
      response = DemoController::Edit.instance.call(context).as(String)
      response.should contain "New"
    end
  end

  describe DemoController::Update do
    it "updates demo" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      request = HTTP::Request.new("PUT", "/demos/#{demo.id}")
      io, context = create_context(request)
      context.params["id"] = demo.id.to_s
      context.params["name"] = "test2"
      response = DemoController::Update.instance.call(context).as(String)
      demo = Demo.find(demo.id).not_nil!
      demo.name.should eq "test2"
    end
  end

  describe DemoController::Delete do
    it "" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      request = HTTP::Request.new("DELETE", "/demos/#{demo.id}")
      io, context = create_context(request)
      context.params["id"] = demo.id.to_s
      response = DemoController::Delete.instance.call(context).as(String)
      demo = Demo.find demo.id
      demo.should eq nil
    end
  end
end
