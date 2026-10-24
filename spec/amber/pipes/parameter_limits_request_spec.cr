require "../../spec_helper"

private MAX_REJECTION_BYTES = 8_u64 * 1024 * 1024

class ParameterLimitsSchema < Amber::Schema::Definition
  content_type "application/x-www-form-urlencoded"
  field :title, String
end

class ParameterLimitsController < Amber::Controller::Base
  schema :create, ParameterLimitsSchema

  class_property action_calls = 0

  def create
    self.class.action_calls += 1
    "created"
  end

  class_property list_of_upload_paths = [] of String

  def upload
    self.class.list_of_upload_paths << params.files["doc"].file.path
    "uploaded"
  end

  def index
    count = params.fetch_all("a").size
    self.class.action_calls += 1
    count.to_s
  end
end

# Sends a URL-encoded POST through routing, the CSRF pipe, and the schema
# contract, carrying a valid CSRF token in the body as a browser form would.
private def post_form(pipeline : Amber::Pipe::Pipeline, fields : String) : HTTP::Client::Response
  request = HTTP::Request.new("POST", "/parameter-limits", HTTP::Headers{
    "Content-Type" => "application/x-www-form-urlencoded",
    "Accept"       => "application/json",
  })
  io = IO::Memory.new
  context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(io))
  token = Amber::Pipe::CSRF.token(context).to_s
  request.body = IO::Memory.new("_csrf=#{URI.encode_www_form(token)}&#{fields}")

  pipeline.call(context)
  context.response.close
  io.rewind
  HTTP::Client::Response.from_io(io, decompress: false)
end

describe "request parameter limits on the request path" do
  pipeline = Amber::Pipe::Pipeline.new

  before_each do
    Amber.env = :test
    ParameterLimitsController.action_calls = 0
    pipeline = Amber::Pipe::Pipeline.new
    Amber::Server.router.draw :web do
      post "/parameter-limits", ParameterLimitsController, :create
      get "/parameter-limits", ParameterLimitsController, :index
      post "/parameter-limits/upload", ParameterLimitsController, :upload
    end
    pipeline.build :web do
      plug Amber::Pipe::CSRF.new
    end
    pipeline.prepare_pipelines
  end

  it "accepts an ordinary form" do
    response = post_form(pipeline, "title=hello&items[0]=a&items[1]=b")

    response.status_code.should eq 200
    ParameterLimitsController.action_calls.should eq 1
  end

  {
    "a huge index"        => "items[999999999]=x",
    "an Int64 overflow"   => "items[9999999999999999999999]=x",
    "a negative index"    => "items[-1]=x",
    "a deeply nested key" => "a#{"[b]" * 40}=x",
  }.each do |description, fields|
    it "answers 400 for #{description} without reaching the action" do
      list_of_responses = [] of HTTP::Client::Response
      allocated = bytes_allocated_by do
        list_of_responses << post_form(pipeline, fields)
      end
      response = list_of_responses.first

      response.status_code.should eq 400
      response.body.should contain("parameter_limit_exceeded")
      ParameterLimitsController.action_calls.should eq 0
      allocated.should be < MAX_REJECTION_BYTES
    end
  end

  it "answers 400 for a huge parameter count while routing reads the form" do
    fields = (0..1_000).map { |i| "f#{i}=x" }.join("&")
    list_of_responses = [] of HTTP::Client::Response
    allocated = bytes_allocated_by do
      list_of_responses << post_form(pipeline, fields)
    end
    response = list_of_responses.first

    response.status_code.should eq 400
    response.body.should contain("max_params")
    ParameterLimitsController.action_calls.should eq 0
    allocated.should be < MAX_REJECTION_BYTES
  end

  it "answers 400 when a controller reads an oversized query string" do
    query = (0..1_000).map { "a=1" }.join("&")
    response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/parameter-limits?#{query}", HTTP::Headers{"Accept" => "application/json"}))

    response.status_code.should eq 400
    response.body.should contain("max_params")
    ParameterLimitsController.action_calls.should eq 0
  end

  it "serves an ordinary query string" do
    response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/parameter-limits?a=1&a=2"))

    response.status_code.should eq 200
    response.body.should eq "2"
  end

  it "removes upload tempfiles when the request finishes" do
    ParameterLimitsController.list_of_upload_paths.clear
    boundary = "AmberCleanupBoundary"
    request = HTTP::Request.new("POST", "/parameter-limits/upload", HTTP::Headers{
      "Content-Type" => "multipart/form-data; boundary=#{boundary}",
    })
    io = IO::Memory.new
    context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(io))
    token = Amber::Pipe::CSRF.token(context).to_s
    request.body = IO::Memory.new(
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\n#{token}\r\n" \
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"a.txt\"\r\n\r\nfile body\r\n" \
      "--#{boundary}--\r\n"
    )

    pipeline.call(context)

    context.response.status_code.should eq 200
    path = ParameterLimitsController.list_of_upload_paths.first
    File.exists?(path).should be_false
  end

  it "answers 400 for malformed multipart metadata" do
    boundary = "AmberMalformedBoundary"
    request = HTTP::Request.new("POST", "/parameter-limits/upload", HTTP::Headers{
      "Content-Type" => "multipart/form-data; boundary=#{boundary}",
      "Accept"       => "application/json",
    })
    request.body = IO::Memory.new(
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"x\"; size=bogus\r\n\r\nx\r\n--#{boundary}--\r\n"
    )
    response = create_request_and_return_io(pipeline, request)

    response.status_code.should eq 400
    response.body.should contain("malformed")
  end
end
