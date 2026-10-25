require "../../spec_helper"

private MAX_REJECTION_BYTES = 8_u64 * 1024 * 1024

# A rejected 24 MiB form value: the scanner grows its buffer to the raw
# value cap (three times max_value_bytes) before rejecting, about 8 MiB in
# all, whatever the body's size. Reading the body whole would allocate
# more than 24 MiB.
private MAX_FORM_REJECTION_BYTES = 12_u64 * 1024 * 1024

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
  class_property kept_upload_destination = ""

  def upload
    upload = params.files["doc"]
    self.class.list_of_upload_paths << upload.path
    upload.file.gets_to_end
  end

  def keep_upload
    params.files["doc"].move_to(self.class.kept_upload_destination)
  end

  def retain_upload
    params.files["doc"].retain!
  end

  def update
    title = request.form_params["title"]?
    self.class.action_calls += 1
    title || "no title"
  end

  def direct_parse
    config = Amber::Configuration::ParamsConfig.new
    config.max_document_body_bytes = 16
    request.param_budget = Amber::Router::Parsers::ParamBudget.new(config)
    Amber::Schema::Parser::ParserRegistry.parse_request(request)
    "parsed"
  end

  def plain
    self.class.action_calls += 1
    params["title"]? || "no title"
  end

  def index
    count = params.fetch_all("a").size
    self.class.action_calls += 1
    count.to_s
  end
end

# Reads the URL-encoded body in a pipe, before routing and CSRF, the way
# third-party middleware calls `HTTP::Request#form_params`.
class FormReadingPipe < Amber::Pipe::Base
  class_property list_of_titles = [] of String?

  def call(context : HTTP::Server::Context)
    self.class.list_of_titles << context.request.form_params["title"]?
    call_next(context)
  end
end

# Sends a URL-encoded POST through routing, the CSRF pipe, and the schema
# contract, carrying a valid CSRF token in the body as a browser form would.
private def post_form(pipeline : Amber::Pipe::Pipeline, fields : String, method : String = "POST", path : String = "/parameter-limits") : HTTP::Client::Response
  request = HTTP::Request.new(method, path, HTTP::Headers{
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

# Sends *body* as a URL-encoded form without copying it, carrying the CSRF
# token in its header, so an allocation measurement sees only Amber's work.
private def send_large_form(pipeline : Amber::Pipe::Pipeline, method : String, path : String, body : String) : HTTP::Client::Response
  request = HTTP::Request.new(method, path, HTTP::Headers{
    "Content-Type" => "application/x-www-form-urlencoded",
    "Accept"       => "application/json",
  })
  io = IO::Memory.new
  context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(io))
  request.headers[Amber::Pipe::CSRF::HEADER_KEY] = Amber::Pipe::CSRF.token(context).to_s
  request.body = IO::Memory.new(body)

  pipeline.call(context)
  context.response.close
  io.rewind
  HTTP::Client::Response.from_io(io, decompress: false)
end

# Posts one file part, with a valid CSRF token, to *path*.
private def post_upload(pipeline : Amber::Pipe::Pipeline, path : String, content : String) : HTTP::Client::Response
  boundary = "AmberUploadBoundary"
  request = HTTP::Request.new("POST", path, HTTP::Headers{
    "Content-Type" => "multipart/form-data; boundary=#{boundary}",
  })
  io = IO::Memory.new
  context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(io))
  token = Amber::Pipe::CSRF.token(context).to_s
  request.body = IO::Memory.new(
    "--#{boundary}\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\n#{token}\r\n" \
    "--#{boundary}\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"a.txt\"\r\n\r\n#{content}\r\n" \
    "--#{boundary}--\r\n"
  )

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
      post "/parameter-limits/keep", ParameterLimitsController, :keep_upload
      post "/parameter-limits/retain", ParameterLimitsController, :retain_upload
      put "/parameter-limits/update", ParameterLimitsController, :update
      post "/parameter-limits/plain", ParameterLimitsController, :plain
      post "/parameter-limits/direct", ParameterLimitsController, :direct_parse
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
      # Routing reads the form for `_method` and its admission check
      # rejects the pair before the schema contract runs.
      response.body.should match(/max_array_index|max_nesting_depth/)
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

  it "lets the action read an upload through file, then removes it when the request finishes" do
    ParameterLimitsController.list_of_upload_paths.clear
    response = post_upload(pipeline, "/parameter-limits/upload", "file body")

    response.status_code.should eq 200
    response.body.should eq "file body"
    path = ParameterLimitsController.list_of_upload_paths.first
    File.exists?(path).should be_false
  end

  it "keeps an upload the action moved with move_to" do
    destination = File.tempname("amber-kept-upload", ".txt")
    ParameterLimitsController.kept_upload_destination = destination
    response = post_upload(pipeline, "/parameter-limits/keep", "keep me")

    response.status_code.should eq 200
    response.body.should eq destination
    File.read(destination).should eq "keep me"
    File.delete(destination)
  end

  it "keeps an upload the action retained for later use" do
    response = post_upload(pipeline, "/parameter-limits/retain", "for a job")

    response.status_code.should eq 200
    File.read(response.body).should eq "for a job"
    File.delete(response.body)
  end

  it "reads a PUT form through the bounded parse in the action" do
    response = post_form(pipeline, "title=hello", "PUT", "/parameter-limits/update")

    response.status_code.should eq 200
    response.body.should eq "hello"
  end

  it "answers 400 for an oversized PUT form an action reads with request.form_params" do
    # No pipes, as on an API valve: the action is the first to read the body.
    api_pipeline = Amber::Pipe::Pipeline.new
    api_pipeline.build(:web) { }
    api_pipeline.prepare_pipelines
    body = "title=#{"x" * 24 * 1024 * 1024}"
    list_of_responses = [] of HTTP::Client::Response
    allocated = bytes_allocated_by do
      list_of_responses << send_large_form(api_pipeline, "PUT", "/parameter-limits/update", body)
    end
    response = list_of_responses.first

    response.status_code.should eq 400
    ParameterLimitsController.action_calls.should eq 0
    allocated.should be < MAX_FORM_REJECTION_BYTES
  end

  it "bounds a middleware read of the form and shares the parse with the action" do
    FormReadingPipe.list_of_titles.clear
    reading_pipeline = Amber::Pipe::Pipeline.new
    reading_pipeline.build :web do
      plug FormReadingPipe.new
      plug Amber::Pipe::CSRF.new
    end
    reading_pipeline.prepare_pipelines

    response = post_form(reading_pipeline, "title=hello", "PUT", "/parameter-limits/update")
    response.status_code.should eq 200
    response.body.should eq "hello"
    FormReadingPipe.list_of_titles.should eq ["hello"]

    body = "title=#{"x" * 24 * 1024 * 1024}"
    list_of_responses = [] of HTTP::Client::Response
    allocated = bytes_allocated_by do
      list_of_responses << send_large_form(reading_pipeline, "PUT", "/parameter-limits/update", body)
    end
    list_of_responses.first.status_code.should eq 400
    FormReadingPipe.list_of_titles.size.should eq 1
    allocated.should be < MAX_FORM_REJECTION_BYTES
  end

  {
    "a key nested 40 deep" => "a#{"[b]" * 40}=x",
    "an oversized index"   => "items[999999999]=x",
  }.each do |description, fields|
    it "answers 400 for #{description} on an ordinary route's query and form" do
      query_response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/parameter-limits?#{fields}", HTTP::Headers{"Accept" => "application/json"}))
      query_response.status_code.should eq 400

      form_response = post_form(pipeline, fields, "POST", "/parameter-limits/plain")
      form_response.status_code.should eq 400
      ParameterLimitsController.action_calls.should eq 0
    end
  end

  it "answers 400, not 500, when an action's direct schema parse hits a limit" do
    api_pipeline = Amber::Pipe::Pipeline.new
    api_pipeline.build(:web) { }
    api_pipeline.prepare_pipelines
    error_pipeline = Amber::Pipe::Pipeline.new
    error_pipeline.build(:web) { plug Amber::Pipe::Error.new }
    error_pipeline.prepare_pipelines

    [api_pipeline, error_pipeline].each do |each_pipeline|
      request = HTTP::Request.new("POST", "/parameter-limits/direct", HTTP::Headers{
        "Content-Type" => "application/json",
        "Accept"       => "application/json",
      }, %({"title":"seventeen"}))
      response = create_request_and_return_io(each_pipeline, request)

      response.status_code.should eq 400
      response.body.should contain("max_document_body_bytes")
    end
  end

  describe "WebSocket upgrades through the pipeline" do
    upgrade_headers = HTTP::Headers{
      "Upgrade"               => "WebSocket",
      "Connection"            => "keep-alive, Upgrade",
      "Sec-WebSocket-Version" => HTTP::WebSocket::Protocol::VERSION,
      "Sec-WebSocket-Key"     => "dGhlIHNhbXBsZSBub25jZQ==",
    }

    it "upgrades a mixed-case handshake on a socket-only route" do
      Amber::WebSockets::Server::Handler.new("/parameter-limits-chat") { |_socket, _context| }
      context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/parameter-limits-chat", upgrade_headers), HTTP::Server::Response.new(IO::Memory.new))

      pipeline.call(context)

      context.response.status.should eq HTTP::Status::SWITCHING_PROTOCOLS
    end

    it "answers 400 for an oversized query on a socket-only route before switching protocols" do
      Amber::WebSockets::Server::Handler.new("/parameter-limits-chat") { |_socket, _context| }
      query = Array.new(1_001, "a=1").join("&")
      context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/parameter-limits-chat?#{query}", upgrade_headers), HTTP::Server::Response.new(IO::Memory.new))

      pipeline.call(context)

      context.response.status_code.should eq 400
      context.response.upgrade_handler.should be_nil
    end

    it "answers 404, not 500, for a plain request to a socket-only route" do
      Amber::WebSockets::Server::Handler.new("/parameter-limits-chat") { |_socket, _context| }
      response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/parameter-limits-chat"))

      response.status_code.should eq 404
    end
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
