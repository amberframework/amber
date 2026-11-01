require "yaml"
require "../support/trusted_proxy_network"

module Amber::Configuration
  class SSLConfig
    include YAML::Serializable

    property key_file : String? = nil
    property cert_file : String? = nil

    def initialize
    end

    def is_enabled? : Bool
      !key_file.nil? && !cert_file.nil?
    end
  end

  class ServerConfig
    include YAML::Serializable

    # Loopback only: a reverse proxy on the same host (Caddy, nginx) is
    # trusted out of the box, and nothing else is.
    DEFAULT_TRUSTED_PROXIES = ["127.0.0.0/8", "::1"]

    # `trusted_proxy_headers` value for proxies that write `X-Forwarded-For`
    # and `X-Forwarded-Proto` (Caddy, nginx, HAProxy, cloud load balancers).
    TRUSTED_PROXY_HEADERS_X_FORWARDED = "x-forwarded"

    # `trusted_proxy_headers` value for proxies that write the RFC 7239
    # `Forwarded` header instead.
    TRUSTED_PROXY_HEADERS_FORWARDED = "forwarded"

    LIST_OF_TRUSTED_PROXY_HEADERS = [TRUSTED_PROXY_HEADERS_X_FORWARDED, TRUSTED_PROXY_HEADERS_FORWARDED]

    property host : String = "localhost"
    property port : Int32 = 3000
    property port_reuse : Bool = true
    property process_count : Int32 = 1
    property secret_key_base : String = ""

    @[YAML::Field(key: "ssl")]
    property ssl : SSLConfig = SSLConfig.new

    # The `trusted_proxies` list as written in YAML. Requests never read it;
    # they read `@trusted_proxy_snapshot`, which is rebuilt from it at load
    # and on every assignment.
    @[YAML::Field(key: "trusted_proxies")]
    @trusted_proxy_notations : Array(String) = DEFAULT_TRUSTED_PROXIES.dup

    # Which forwarding headers the trusted proxies write: `"x-forwarded"`
    # (the default) or `"forwarded"`. See `#trusted_proxy_headers=`.
    @[YAML::Field(key: "trusted_proxy_headers")]
    @trusted_proxy_headers : String = TRUSTED_PROXY_HEADERS_X_FORWARDED

    # Path of a UNIX socket to listen on instead of `host` and `port`, for a
    # reverse proxy on the same machine (`reverse_proxy unix//run/app.sock`
    # in Caddy). While it is set, every UNIX socket peer counts as a trusted
    # proxy: such a connection is local by construction, and the socket
    # file's permissions decide who may open it.
    property unix_socket : String? = nil

    # The validated, parsed form of `trusted_proxies`. Nothing changes it
    # after it is built: an assignment builds a new one and replaces the
    # reference, so a request running on another thread sees either the old
    # list or the new one, never a list in the middle of an edit.
    private class TrustedProxySnapshot
      getter list_of_notations : Array(String)
      getter list_of_networks : Array(Amber::Support::TrustedProxyNetwork)

      # Parses *list_of_notations*, raising
      # `Amber::Exceptions::ConfigurationError` naming the first entry that is
      # not an IP address or CIDR block, or that trusts every address.
      def self.parse(list_of_notations : Array(String)) : self
        list_of_networks = list_of_notations.map do |notation|
          network = Amber::Support::TrustedProxyNetwork.parse(notation)
          if network.covers_every_address?
            raise Amber::Exceptions::ConfigurationError.new(
              "server.trusted_proxies entry #{notation.inspect} trusts every address, so any client could " \
              "choose its own scheme and address; list the proxy's own addresses or network instead"
            )
          end
          network
        end
        new(list_of_notations.dup, list_of_networks)
      end

      private def initialize(@list_of_notations : Array(String), @list_of_networks : Array(Amber::Support::TrustedProxyNetwork))
      end
    end

    @[YAML::Field(ignore: true)]
    @trusted_proxy_snapshot : TrustedProxySnapshot = TrustedProxySnapshot.parse(DEFAULT_TRUSTED_PROXIES)

    def initialize
    end

    # Validates the forwarding settings read from YAML, so a bad entry fails
    # while the settings load rather than on a request.
    def after_initialize
      @trusted_proxy_snapshot = TrustedProxySnapshot.parse(@trusted_proxy_notations)
      self.class.check_trusted_proxy_headers!(@trusted_proxy_headers)
    end

    # Returns a copy of the IP addresses and CIDR blocks of the reverse
    # proxies allowed to report the client's scheme and address. Assign a new
    # list to change it; editing the returned array changes nothing.
    #
    # ```yaml
    # server:
    #   trusted_proxies:
    #     - "127.0.0.1"
    #     - "10.0.0.0/8"
    # ```
    def trusted_proxies : Array(String)
      @trusted_proxy_snapshot.list_of_notations.dup
    end

    # Replaces the trusted proxy list. Raises
    # `Amber::Exceptions::ConfigurationError` when an entry is not an IP
    # address or CIDR block, or is a `/0` block that trusts every address.
    def trusted_proxies=(list_of_notations : Array(String)) : Array(String)
      snapshot = TrustedProxySnapshot.parse(list_of_notations)
      @trusted_proxy_notations = snapshot.list_of_notations.dup
      @trusted_proxy_snapshot = snapshot
      list_of_notations
    end

    # Returns the trusted proxies parsed into networks. The array belongs to
    # an immutable snapshot; do not modify it.
    def trusted_proxy_networks : Array(Amber::Support::TrustedProxyNetwork)
      @trusted_proxy_snapshot.list_of_networks
    end

    # Returns which forwarding headers the trusted proxies write:
    # `"x-forwarded"` (`X-Forwarded-For` and `X-Forwarded-Proto`, the default)
    # or `"forwarded"` (RFC 7239 `Forwarded`). Amber reads only that family,
    # because a proxy passes the other family through from the client
    # unchanged, so believing it would let the client choose its own address
    # and scheme.
    def trusted_proxy_headers : String
      @trusted_proxy_headers
    end

    # Sets which forwarding headers the trusted proxies write. Raises
    # `Amber::Exceptions::ConfigurationError` for a value other than
    # `"x-forwarded"` or `"forwarded"`.
    def trusted_proxy_headers=(header_family : String) : String
      self.class.check_trusted_proxy_headers!(header_family)
      @trusted_proxy_headers = header_family
    end

    # Returns `true` when the trusted proxies write the RFC 7239 `Forwarded`
    # header rather than the `X-Forwarded-*` headers.
    def reads_forwarded_header? : Bool
      @trusted_proxy_headers == TRUSTED_PROXY_HEADERS_FORWARDED
    end

    # :nodoc:
    def self.check_trusted_proxy_headers!(header_family : String) : Nil
      return if LIST_OF_TRUSTED_PROXY_HEADERS.includes?(header_family)

      raise Amber::Exceptions::ConfigurationError.new(
        "server.trusted_proxy_headers must be one of #{LIST_OF_TRUSTED_PROXY_HEADERS.join(", ")}, got #{header_family.inspect}"
      )
    end

    # Returns `true` when the server listens on `unix_socket` rather than TCP.
    def listens_on_unix_socket? : Bool
      socket_path = unix_socket
      !socket_path.nil? && !socket_path.empty?
    end

    # Raises `Amber::Exceptions::ConfigurationError` when a server listening
    # on `unix_socket` would also terminate TLS or run more than one process.
    # `Amber::Server#run` calls it with the effective settings before it
    # forks or binds.
    def self.check_unix_socket!(terminates_tls : Bool, process_count : Int32) : Nil
      if terminates_tls
        raise Amber::Exceptions::ConfigurationError.new(
          "server.unix_socket cannot be combined with server.ssl; terminate TLS at the proxy"
        )
      end

      unless process_count == 1
        raise Amber::Exceptions::ConfigurationError.new(
          "server.unix_socket requires server.process_count 1, got #{process_count}"
        )
      end
    end

    def validate!(environment : Amber::Environment::Env? = nil) : Nil
      unless @port.in?(1..65535)
        raise Amber::Exceptions::ConfigurationError.new(
          "server.port must be between 1 and 65535, got #{@port}"
        )
      end

      unless @process_count >= 1
        raise Amber::Exceptions::ConfigurationError.new(
          "server.process_count must be at least 1, got #{@process_count}"
        )
      end

      if environment && environment.production?
        if @secret_key_base.empty?
          raise Amber::Exceptions::ConfigurationError.new(
            "server.secret_key_base must be set in production"
          )
        end
      end

      if !@secret_key_base.empty? && @secret_key_base.size < 32
        raise Amber::Exceptions::ConfigurationError.new(
          "server.secret_key_base should be at least 32 characters, got #{@secret_key_base.size}"
        )
      end

      if listens_on_unix_socket?
        self.class.check_unix_socket!(ssl.is_enabled?, @process_count)
      end

      if ssl.is_enabled?
        if ssl.key_file && !File.exists?(ssl.key_file.not_nil!)
          raise Amber::Exceptions::ConfigurationError.new(
            "server.ssl.key_file does not exist: #{ssl.key_file}"
          )
        end
        if ssl.cert_file && !File.exists?(ssl.cert_file.not_nil!)
          raise Amber::Exceptions::ConfigurationError.new(
            "server.ssl.cert_file does not exist: #{ssl.cert_file}"
          )
        end
      end
    end
  end
end
