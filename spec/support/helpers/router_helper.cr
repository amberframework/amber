module RouterHelper
  def create_request_and_return_io(router, request)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    router.call(context)
    response.close
    io.rewind
    HTTP::Client::Response.from_io(io, decompress: false)
  end

  def make_router_call(router, request, token : (String | Nil) = nil)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    unless token.nil?
      context.session["csrf.token"] = token
      context.params["_csrf"] = token
    end
    router.call(context)
  end

  def create_context(request)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    HTTP::Server::Context.new(request, response)
  end

  def url_encoded_form_post
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    body = "cat=1&cat=0&cat=-1&test_form=test1&test_form=test2&test_both=form1&test_both=form2"
    request = HTTP::Request.new("GET",
      "/?test=test&test=test2&test_both=query&test_both=query1&#{HTTP::Request::METHOD}=put&status=1234",
      headers,
      body)
    Amber::Router::Params.new(request)
  end

  def multipart_form_post
    headers = HTTP::Headers.new
    headers["Content-Type"] = "multipart/form-data; boundary=fhhRFLCazlkA0dX; charset=UTF-8"
    multipart_content = ::File.read(::File.expand_path("spec/support/sample/multipart.txt"))
    multipart_body = multipart_content.gsub("\n", "\r\n")
    request = HTTP::Request.new("POST", "/?test=test&test=test2&#{HTTP::Request::METHOD}=put&status=1234", headers, multipart_body)
    Amber::Router::Params.new(request)
  end

  def cors_context(method = "GET", **args)
    headers = HTTP::Headers.new
    args.each do |k, v|
      headers[k.to_s] = v
    end
    request = HTTP::Request.new(method, "/", headers)
    create_context(request)
  end

  def assert_cors_success(context)
    origin_header = context.response.headers["Access-Control-Allow-Origin"]?
    origin_header.should_not be_nil
  end

  def assert_non_cors_request(context)
    origin_header = context.response.headers["Access-Control-Allow-Origin"]?
    context.response.status_code.should eq 200
    origin_header.should be_nil
  end

  def assert_cors_failure(context)
    origin_header = context.response.headers["Access-Control-Allow-Origin"]?
    context.response.status_code.should eq 403
    origin_header.should be_nil
  end

  def origins
    domain = "example.com"
    origins = Amber::Pipe::CORS::OriginType.new
    origins << domain
  end

  def cors_add_next(cors)
    cors.next = ->(_context : HTTP::Server::Context) { "test" }
    cors
  end
end
