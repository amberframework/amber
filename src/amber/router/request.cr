require "./params"
require "./router"
require "./route"
require "./request_scheme"
require "./client_address"

class HTTP::Request
  METHOD          = "_method"
  OVERRIDE_HEADER = "X-HTTP-Method-Override"

  @matched_route : Amber::Router::RoutedResult(Amber::Route)?
  @requested_method : String?
  @effective_method : String?
  @params : Amber::Router::Params?

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

  # Returns the scheme the client used to reach the application, `"https"` or
  # `"http"`.
  #
  # Behind a TLS-terminating reverse proxy the connection Amber sees is plain
  # HTTP, so the scheme the proxy reports (`Forwarded: proto=`,
  # `X-Forwarded-Proto`, or `HTTPS: on`) is believed only when the immediate
  # peer is a trusted proxy (`server.trusted_proxies`). See
  # `Amber::Router::RequestScheme`.
  def scheme : String
    Amber::Router::RequestScheme.resolve(self, trusted_proxies, Amber.settings.server_terminates_tls?)
  end

  # Returns `true` when the client reached the application over HTTPS. This
  # is the one place Amber answers that question; see `#scheme`.
  def https? : Bool
    scheme == Amber::Router::RequestScheme::HTTPS
  end

  # Returns the IP address of the client, or `nil` when none is known.
  #
  # From an untrusted peer this is the peer's own address. From a trusted
  # proxy it is the nearest untrusted hop in `Forwarded: for=` or
  # `X-Forwarded-For`, read from the right. See `Amber::Router::ClientAddress`.
  def client_ip : Socket::IPAddress?
    Amber::Router::ClientAddress.resolve(self, trusted_proxies)
  end

  # The proxies this application trusts, from `server.trusted_proxies` and
  # `server.unix_socket`.
  def trusted_proxies : Amber::Support::TrustedProxies
    server_config = Amber.settings.server
    Amber::Support::TrustedProxies.new(
      server_config.trusted_proxy_networks,
      trusts_unix_socket_peers: server_config.listens_on_unix_socket?
    )
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
