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

      get "/demos"
      response.body.should contain "test"
    end
  end

  describe DemoController::Show do
    it "renders a single demo" do
      demo = Demo.new
      demo.name = "test"
      demo.save

      get "/demos/#{demo.id}"
      response.body.should contain "test"
    end
  end

  describe DemoController::New do
    it "render new template" do
      get "/demos/new"
      response.body.should contain "New Demo"
    end
  end

  describe DemoController::Create do
    it "creates a demo" do
      post "/demos", body: {name: "testing"}
      demo = Demo.all
      demo.size.should eq 1
    end
  end

  describe DemoController::Edit do
    it "renders edit template" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      get "/demos/#{demo.id}/edit"
      response.body.should contain "Edit Demo"
    end
  end

  describe DemoController::Update do
    it "updates a demo" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      put "/demos/#{demo.id}", body: {name: "test2"}
      demo = Demo.find(demo.id).not_nil!
      demo.name.should eq "test2"
    end
  end

  describe DemoController::Delete do
    it "deletes a demo" do
      demo = Demo.new
      demo.name = "test"
      demo.save
      delete "/demos/#{demo.id}"
      demo = Demo.find demo.id
      demo.should eq nil
    end
  end
end
