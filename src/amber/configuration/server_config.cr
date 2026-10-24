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

    property host : String = "localhost"
    property port : Int32 = 3000
    property port_reuse : Bool = true
    property process_count : Int32 = 1
    property secret_key_base : String = ""

    @[YAML::Field(key: "ssl")]
    property ssl : SSLConfig = SSLConfig.new

    # IP addresses and CIDR blocks of the reverse proxies allowed to tell
    # Amber which scheme the client used. When the immediate peer of a
    # request matches an entry, Amber believes the `Forwarded: proto=` or
    # `X-Forwarded-Proto` value that proxy appended; requests from any other
    # peer keep their real scheme. See `HTTP::Request#https?`.
    #
    # ```yaml
    # server:
    #   trusted_proxies:
    #     - "127.0.0.1"
    #     - "10.0.0.0/8"
    # ```
    property trusted_proxies : Array(String) = DEFAULT_TRUSTED_PROXIES.dup

    # Path of a UNIX socket to listen on instead of `host` and `port`, for a
    # reverse proxy on the same machine (`reverse_proxy unix//run/app.sock`
    # in Caddy). While it is set, every UNIX socket peer counts as a trusted
    # proxy: such a connection is local by construction, and the socket
    # file's permissions decide who may open it.
    property unix_socket : String? = nil

    # The parsed form of `trusted_proxies` together with the list it was
    # parsed from. It is a class so that replacing the cache is a single
    # reference write, which a concurrent reader can never observe half done.
    private class ParsedTrustedProxies
      getter list_of_notations : Array(String)
      getter list_of_networks : Array(Amber::Support::TrustedProxyNetwork)

      def initialize(@list_of_notations, @list_of_networks)
      end
    end

    @[YAML::Field(ignore: true)]
    @parsed_trusted_proxies : ParsedTrustedProxies? = nil

    def initialize
    end

    # Returns `trusted_proxies` parsed into networks. Raises
    # `Amber::Exceptions::ConfigurationError` when an entry is not an IP
    # address or CIDR block.
    def trusted_proxy_networks : Array(Amber::Support::TrustedProxyNetwork)
      cached = @parsed_trusted_proxies
      if cached && cached.list_of_notations == trusted_proxies
        return cached.list_of_networks
      end

      list_of_notations = trusted_proxies.dup
      list_of_networks = list_of_notations.map { |notation| Amber::Support::TrustedProxyNetwork.parse(notation) }
      @parsed_trusted_proxies = ParsedTrustedProxies.new(list_of_notations, list_of_networks)
      list_of_networks
    end

    # Returns `true` when the server listens on `unix_socket` rather than TCP.
    def listens_on_unix_socket? : Bool
      socket_path = unix_socket
      !socket_path.nil? && !socket_path.empty?
    end

    # Raises `Amber::Exceptions::ConfigurationError` when `unix_socket` is
    # combined with settings that only work over TCP.
    private def validate_unix_socket! : Nil
      return unless listens_on_unix_socket?

      if ssl.is_enabled?
        raise Amber::Exceptions::ConfigurationError.new(
          "server.unix_socket cannot be combined with server.ssl; terminate TLS at the proxy"
        )
      end

      unless @process_count == 1
        raise Amber::Exceptions::ConfigurationError.new(
          "server.unix_socket requires server.process_count 1, got #{@process_count}"
        )
      end
    end

    # Raises `Amber::Exceptions::ConfigurationError` naming the first
    # `trusted_proxies` entry that is not an IP address or CIDR block.
    private def validate_trusted_proxies! : Nil
      trusted_proxies.each do |notation|
        Amber::Support::TrustedProxyNetwork.parse(notation)
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

      validate_trusted_proxies!
      validate_unix_socket!

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
