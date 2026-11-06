require "yaml"
require "http/headers"

module Amber::Configuration
  # Holds the response header values that `Amber::Pipe::SecurityHeaders`
  # sends. The defaults stop MIME sniffing, refuse framing by any site
  # (including the application's own pages), trim the referrer and, on
  # HTTPS, pin the host to HTTPS. Headers that turn off browser features
  # (`Permissions-Policy`) or popup relationships
  # (`Cross-Origin-Opener-Policy`) are opt-in, because their strict values
  # break payment, camera, location and popup sign-in flows.
  #
  # An application changes a value in `config/environments/<env>.yml`:
  #
  # ```yaml
  # security_headers:
  #   frame_options: "SAMEORIGIN"
  #   content_security_policy: "frame-ancestors 'self'"
  # ```
  #
  # or with an `AMBER_SECURITY_HEADERS_<KEY>` environment variable, such as
  # `AMBER_SECURITY_HEADERS_FRAME_OPTIONS=SAMEORIGIN`.
  #
  # An empty string turns that one header off. `strict_transport_security`
  # is sent only on requests that `HTTP::Request#https?` reports as HTTPS.
  #
  # Every value is checked when the settings load and whenever it is
  # assigned: a value with a line break or another character HTTP headers do
  # not allow raises `Amber::Exceptions::ConfigurationError` then, rather
  # than failing each response later.
  class SecurityHeadersConfig
    # A misspelled key fails the load instead of leaving that header at its
    # default without a word.
    include YAML::Serializable
    include YAML::Serializable::Strict

    # Value of `X-Content-Type-Options`.
    getter content_type_options : String = "nosniff"

    # Value of `X-Frame-Options`, for browsers that predate CSP
    # `frame-ancestors`.
    getter frame_options : String = "DENY"

    # Value of `Content-Security-Policy`. The default carries only
    # `frame-ancestors`, the modern form of `X-Frame-Options`, so it changes
    # nothing about which scripts, styles or images a page may load.
    getter content_security_policy : String = "frame-ancestors 'none'"

    # Value of `Referrer-Policy`.
    getter referrer_policy : String = "strict-origin-when-cross-origin"

    # Value of `Permissions-Policy`. Empty by default, so not sent: denying a
    # feature such as `payment` or `camera` breaks the pages that use it (an
    # Apple Pay button, a video call). Name the features the application
    # never uses, for example
    # `"accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"`.
    getter permissions_policy : String = ""

    # Value of `Cross-Origin-Opener-Policy`. Empty by default, so not sent:
    # `same-origin` cuts the link between a page and a popup from another
    # site, which popup sign-in (OAuth) and payment windows rely on. Set
    # `"same-origin"` when the application opens no such popups and is never
    # opened as one.
    getter cross_origin_opener_policy : String = ""

    # Value of `Strict-Transport-Security`, sent on HTTPS requests only,
    # because browsers ignore it over plain HTTP (RFC 6797, section 8.1).
    # The default pins this host for two years and leaves sibling
    # subdomains alone; add `includeSubDomains` once every subdomain of the
    # domain is served over HTTPS (RFC 6797, section 11.4).
    getter strict_transport_security : String = "max-age=63072000"

    {% for key in %w(content_type_options frame_options content_security_policy referrer_policy permissions_policy cross_origin_opener_policy strict_transport_security) %}
      # Sets the `{{key.id}}` value. Raises
      # `Amber::Exceptions::ConfigurationError` when it contains a character
      # HTTP headers do not allow.
      def {{key.id}}=(value : String) : String
        self.class.check_header_value!({{key}}, value)
        @{{key.id}} = value
      end
    {% end %}

    def initialize
    end

    # Rejects a bad value read from YAML while the settings load.
    def after_initialize
      validate!
    end

    # Returns each always-sent header name paired with its configured value,
    # leaving out the headers whose value is empty.
    def list_of_headers : Array(Tuple(String, String))
      list_of_named_values = [
        {"X-Content-Type-Options", content_type_options},
        {"X-Frame-Options", frame_options},
        {"Content-Security-Policy", content_security_policy},
        {"Referrer-Policy", referrer_policy},
        {"Permissions-Policy", permissions_policy},
        {"Cross-Origin-Opener-Policy", cross_origin_opener_policy},
      ]
      list_of_named_values.reject { |_header_name, value| value.empty? }
    end

    # Returns `true` when `Strict-Transport-Security` has a value to send.
    def sends_strict_transport_security? : Bool
      !strict_transport_security.empty?
    end

    # Raises `Amber::Exceptions::ConfigurationError` listing every value that
    # contains a line break or another character HTTP headers do not allow.
    def validate! : Nil
      list_of_errors = [] of String
      {
        "content_type_options"       => content_type_options,
        "frame_options"              => frame_options,
        "content_security_policy"    => content_security_policy,
        "referrer_policy"            => referrer_policy,
        "permissions_policy"         => permissions_policy,
        "cross_origin_opener_policy" => cross_origin_opener_policy,
        "strict_transport_security"  => strict_transport_security,
      }.each do |key, value|
        list_of_errors << self.class.invalid_value_message(key) unless self.class.valid_header_value?(value)
      end

      unless list_of_errors.empty?
        raise Amber::Exceptions::ConfigurationError.new(list_of_errors)
      end
    end

    # :nodoc:
    def self.check_header_value!(key : String, value : String) : Nil
      return if valid_header_value?(value)

      raise Amber::Exceptions::ConfigurationError.new(invalid_value_message(key))
    end

    # :nodoc:
    #
    # Returns `true` when *value* holds only characters that `HTTP::Headers`
    # accepts in a header value: tab, printable ASCII and bytes 0x80 to 0xFF.
    def self.valid_header_value?(value : String) : Bool
      HTTP::Headers.new.valid_value?(value)
    end

    # :nodoc:
    def self.invalid_value_message(key : String) : String
      "security_headers.#{key} must not contain a line break or another control character"
    end
  end
end
