require "../../spec_helper"
require "../../../src/amber/testing"

describe Amber::Testing::ContextBuilder do
  describe "#build" do
    it "creates a context with default GET method and root path" do
      context = Amber::Testing::ContextBuilder.new.build
      context.request.method.should eq("GET")
      context.request.path.should eq("/")
    end

    it "sets the HTTP method" do
      context = Amber::Testing::ContextBuilder.new
        .method("POST")
        .build
      context.request.method.should eq("POST")
    end

    it "uppercases the method" do
      context = Amber::Testing::ContextBuilder.new
        .method("post")
        .build
      context.request.method.should eq("POST")
    end

    it "sets the path" do
      context = Amber::Testing::ContextBuilder.new
        .path("/users/1")
        .build
      context.request.path.should eq("/users/1")
    end

    it "sets a single header" do
      context = Amber::Testing::ContextBuilder.new
        .header("Accept", "application/json")
        .build
      context.request.headers["Accept"].should eq("application/json")
    end

    it "sets multiple headers" do
      context = Amber::Testing::ContextBuilder.new
        .header("Accept", "application/json")
        .header("Authorization", "Bearer token123")
        .build
      context.request.headers["Accept"].should eq("application/json")
      context.request.headers["Authorization"].should eq("Bearer token123")
    end

    it "sets the request body" do
      context = Amber::Testing::ContextBuilder.new
        .method("POST")
        .body("key=value")
        .build
      context.request.body.try(&.gets_to_end).should eq("key=value")
    end

    it "sets JSON body and Content-Type header" do
      context = Amber::Testing::ContextBuilder.new
        .method("POST")
        .json_body({name: "Alice", age: 30})
        .build
      context.request.headers["Content-Type"].should eq("application/json")
      body = context.request.body.try(&.gets_to_end)
      body.should_not be_nil
      parsed = JSON.parse(body.not_nil!)
      parsed["name"].as_s.should eq("Alice")
      parsed["age"].as_i.should eq(30)
    end

    it "appends query params to the path" do
      context = Amber::Testing::ContextBuilder.new
        .path("/search")
        .query_param("q", "crystal")
        .query_param("page", "1")
        .build
      context.request.resource.should contain("q=crystal")
      context.request.resource.should contain("page=1")
      context.request.query_params["q"].should eq("crystal")
      context.request.query_params["page"].should eq("1")
    end

    it "appends query params from a hash" do
      params = {"name" => "Alice", "role" => "admin"}
      context = Amber::Testing::ContextBuilder.new
        .path("/users")
        .params(params)
        .build
      context.request.query_params["name"].should eq("Alice")
      context.request.query_params["role"].should eq("admin")
    end

    it "preserves existing query params in the path" do
      context = Amber::Testing::ContextBuilder.new
        .path("/search?q=crystal")
        .query_param("page", "2")
        .build
      context.request.query_params["q"].should eq("crystal")
      context.request.query_params["page"].should eq("2")
    end

    it "returns a context with a writable response" do
      context = Amber::Testing::ContextBuilder.new.build
      context.response.status_code = 201
      context.response.status_code.should eq(201)
    end
  end

  describe "#build_with_io" do
    it "returns context and IO for reading the response" do
      context, io = Amber::Testing::ContextBuilder.new
        .method("GET")
        .path("/test")
        .build_with_io

      context.response.status_code = 200
      context.response.print("Hello, Test!")
      context.response.close

      io.rewind
      client_response = HTTP::Client::Response.from_io(io, decompress: false)
      client_response.status_code.should eq(200)
      client_response.body.should eq("Hello, Test!")
    end
  end

  describe "chaining" do
    it "supports full builder chain" do
      context = Amber::Testing::ContextBuilder.new
        .method("PUT")
        .path("/items/42")
        .header("Accept", "application/json")
        .header("Authorization", "Bearer abc")
        .json_body({title: "Updated"})
        .build

      context.request.method.should eq("PUT")
      context.request.path.should eq("/items/42")
      context.request.headers["Accept"].should eq("application/json")
      context.request.headers["Authorization"].should eq("Bearer abc")
      context.request.headers["Content-Type"].should eq("application/json")
    end
  end
end
