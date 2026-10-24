require "./params"
require "./router"
require "./route"

class HTTP::Request
  METHOD          = "_method"
  OVERRIDE_HEADER = "X-HTTP-Method-Override"

  @matched_route : Amber::Router::RoutedResult(Amber::Route)?
  @requested_method : String?
  @effective_method : String?
  @params : Amber::Router::Params?
  @param_budget : Amber::Router::Parsers::ParamBudget?

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

    if raw_query = query
      param_budget.each_form_pair(IO::Memory.new(raw_query)) { }
    end
    previous_def
  end

  # Removes the tempfiles of this request's uploads. Amber calls it when the
  # request finishes; an action keeps an upload by copying or moving it.
  def delete_uploaded_files : Nil
    if request_params = @params
      request_params.delete_uploaded_files
    end
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
      return true if content_type.starts_with?(Amber::Router::Params::URL_ENCODED_FORM)
      return true if content_type.starts_with?(Amber::Router::Params::MULTIPART_FORM)
    end

    return false unless query_start = @resource.index('?')
    query = @resource.byte_slice(query_start + 1, @resource.bytesize - query_start - 1)
    query.includes?(METHOD) || query.includes?('%')
  end
end
