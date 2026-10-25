require "yaml"

module Amber::Configuration
  # Holds the response header values that `Amber::Pipe::SecurityHeaders`
  # sends. Every value has a secure default, so an application gets the
  # protection by plugging the pipe and configures nothing.
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
  class SecurityHeadersConfig
    include YAML::Serializable

    # Value of `X-Content-Type-Options`.
    property content_type_options : String = "nosniff"

    # Value of `X-Frame-Options`, for browsers that predate CSP
    # `frame-ancestors`.
    property frame_options : String = "DENY"

    # Value of `Content-Security-Policy`. The default carries only
    # `frame-ancestors`, the modern form of `X-Frame-Options`, so it changes
    # nothing about which scripts, styles or images a page may load.
    property content_security_policy : String = "frame-ancestors 'none'"

    # Value of `Referrer-Policy`.
    property referrer_policy : String = "strict-origin-when-cross-origin"

    # Value of `Permissions-Policy`. The default denies the powerful browser
    # features an ordinary web application does not use.
    property permissions_policy : String = "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"

    # Value of `Cross-Origin-Opener-Policy`.
    property cross_origin_opener_policy : String = "same-origin"

    # Value of `Strict-Transport-Security`, sent on HTTPS requests only,
    # because browsers ignore it over plain HTTP (RFC 6797, section 8.1).
    property strict_transport_security : String = "max-age=63072000; includeSubDomains"

    def initialize
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

    # Raises `Amber::Exceptions::ConfigurationError` when a value contains a
    # carriage return or line feed, which would split the response header.
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
        if value.includes?('\r') || value.includes?('\n')
          list_of_errors << "security_headers.#{key} must not contain a line break"
        end
      end

      unless list_of_errors.empty?
        raise Amber::Exceptions::ConfigurationError.new(list_of_errors)
      end
    end
  end
end
