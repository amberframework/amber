require "./params"
require "./router"
require "./route"

class HTTP::Request
  METHOD          = "_method"
  private QUERY_START     = '?'.ord.to_u8
  private FRAGMENT_START  = '#'.ord.to_u8
  OVERRIDE_HEADER = "X-HTTP-Method-Override"

  @matched_route : Amber::Router::RoutedResult(Amber::Route)?
  @requested_method : String?
  @effective_method : String?
  @params : Amber::Router::Params?
  @param_budget : Amber::Router::Parsers::ParamBudget?
  @body_rejection : (Amber::Exceptions::BadRequest | Amber::Schema::RequestParseError)?
  @schema_request_data : Hash(String, JSON::Any)?

  def method
    {% if flag?(:amber_bench_legacy_request_method) %}
      case @method
      when "POST" then requested_method.to_s.upcase
      else             @method
      end
    {% else %}
      return @method unless @method == "POST"

      @effective_method ||= begin
        requested = requested_method
        requested == @method ? @method : requested.upcase
      end
    {% end %}
  end

  # The method on the request line, before any `_method` override.
  def request_line_method : String
    @method
  end

  def requested_method
    {% if flag?(:amber_bench_legacy_request_method) %}
      @requested_method ||= params.override_method?(METHOD) || headers[OVERRIDE_HEADER]? || @method
    {% else %}
      @requested_method ||= begin
        override = params.override_method?(METHOD) if method_override_params?
        override || headers[OVERRIDE_HEADER]? || @method
      end
    {% end %}
  end

  def params
    @params ||= Amber::Router::Params.new(self)
  end

  # The parameter budget shared by every parsing step of this request, so
  # counts and array padding stay cumulative across the query string, the
  # body, and schema conversion.
  def param_budget : Amber::Router::Parsers::ParamBudget
    @param_budget ||= Amber::Router::Parsers::ParamBudget.new
  end

  # Replaces this request's budget, for example from a pipe that gives one
  # route larger limits. Set it before anything reads the request's params.
  def param_budget=(budget : Amber::Router::Parsers::ParamBudget) : Amber::Router::Parsers::ParamBudget
    @param_budget = budget
  end

  # Checks the raw query string pair by pair against `param_budget` before
  # Crystal parses it. A rejected query raises on every access, so a caught
  # error never exposes an unchecked parse.
  def query_params : URI::Params
    if parsed = @query_params
      return parsed
    end

    param_budget.each_form_pair(raw_query_io) { }
    previous_def
  end

  # Runs one read or parse of the request body. A body rejected with
  # `Amber::Exceptions::BadRequest` or `Amber::Schema::RequestParseError`,
  # while it is read or after (a node limit, a CBOR or COSE decoding error),
  # is remembered, and every later guarded read (`params`, `form_params`,
  # schema contracts) raises it again: a caller that catches it never sees
  # a parse of the bytes that remain, or an empty body passed off as valid.
  #
  # When guarded reads nest, the outermost rejection is kept, so a schema
  # parse that maps a limit error to `RequestParseError` raises that same
  # `RequestParseError` again.
  def guard_body_read(& : -> T) : T forall T
    raise_body_rejection!

    begin
      yield
    rescue ex : Amber::Exceptions::BadRequest | Amber::Schema::RequestParseError
      @body_rejection = ex
      raise ex
    end
  end

  # Returns a copy of this request's schema data, computing it with the
  # block only once. Each schema parse of one request then sees the same
  # data, and charges the request's `param_budget` (counts and array
  # padding) only once.
  def schema_request_data(& : -> Hash(String, JSON::Any)) : Hash(String, JSON::Any)
    data = @schema_request_data ||= yield
    data.clone
  end

  # Raises the remembered body rejection, if there is one. Readers of a
  # cached parse call it first, so a body rejected later (for example by a
  # schema contract) is not served from the cache either.
  def raise_body_rejection! : Nil
    if rejection = @body_rejection
      raise rejection
    end
  end

  # Reads a JSON, XML, or other document body through `guard_body_read`,
  # bounded by `max_document_body_bytes`.
  def read_document_body : String
    guard_body_read { param_budget.read_document(body) }
  end

  # Returns the URL-encoded form fields of the body, for any request
  # method, or nil when the body is not `application/x-www-form-urlencoded`
  # or there is no body.
  #
  # Unlike Crystal's version, which reads the whole body into memory, this
  # reuses Amber's bounded parse (`Amber::Router::Params#form_params`), so
  # the body is read once, every pair is checked against `param_budget`,
  # and a middleware read and the action's `params` share one result.
  def form_params? : HTTP::Params?
    raise_body_rejection!
    if parsed = @form_params
      return parsed
    end
    return unless body && params.url_encoded_form?

    @form_params = params.form_params
  end

  # Whether a WebSocket route is registered for this request's path.
  def socket_route? : Bool
    router.socket_route_defined?(self)
  end

  # The raw query as an IO. Before the URI is parsed this reads the request
  # target in place, so a rejected query is never copied.
  private def raw_query_io : IO
    if @uri
      return IO::Memory.new(query || "")
    end

    target = @resource.to_slice
    query_start = target.index(QUERY_START)
    return IO::Memory.new(Bytes.empty) unless query_start

    query_end = target.index(FRAGMENT_START, query_start + 1) || target.size
    IO::Memory.new(target[query_start + 1, query_end - query_start - 1], writable: false)
  end

  # Closes and removes the tempfiles of this request's uploads. Amber calls
  # it when the request finishes; an action keeps an upload with
  # `Amber::Router::File#move_to` or `Amber::Router::File#retain!`.
  def delete_uploaded_files : Nil
    if request_params = @params
      request_params.delete_uploaded_files
    end
    # Tempfiles that could not be deleted earlier, by this request or
    # another, are tried again.
    Amber::Router::File.retry_leftover_deletions
  end

  def port
    # Try to extract port from the Host header first
    if host_with_port = headers["Host"]?
      if match = host_with_port.match(/.*:(\d+)/)
        return match[1].to_i
      end
    end

    # Fall back to parsed_uri for absolute-URI resources
    parsed_uri.port
  end

  def url
    parsed_uri.to_s
  end

  private def parsed_uri
    if resource.starts_with?("http://") || resource.starts_with?("https://")
      URI.parse(resource)
    else
      uri
    end
  end

  def route
    matched_route.payload.not_nil!
  end

  def valid_route?
    matched_route.payload? || router.socket_route_defined?(self)
  end

  def process_websocket
    router.get_socket_handler(self)
  end

  def matched_route
    @matched_route ||= router.match_by_request(self)
  end

  private def router
    Amber::Server.router
  end

  private def method_override_params? : Bool
    if content_type = headers["Content-Type"]?
      return true if Amber::Router::Params.media_type?(content_type, Amber::Router::Params::URL_ENCODED_FORM)
      return true if Amber::Router::Params.media_type?(content_type, Amber::Router::Params::MULTIPART_FORM)
    end

    return false unless query_start = @resource.index('?')
    # Searches the target in place rather than copying the query.
    !!(@resource.index(METHOD, query_start + 1) || @resource.index('%', query_start + 1))
  end
end
