module Amber
  module Pipe
    # Decides whether a response may be compressed for a request, so that a
    # page holding a secret cannot be read out one guessed byte at a time
    # through its compressed size (BREACH, CVE-2013-3587).
    #
    # A BREACH attacker makes the victim's browser send the target many
    # requests from another site, which the browser marks cross-site. Those
    # get the body uncompressed; every request from the site itself, and every
    # top-level page load, stays compressed:
    #
    # * `Sec-Fetch-Site` is `same-origin`, `same-site` or `none`: compress.
    # * `Sec-Fetch-Site` is `cross-site`: compress only a top-level page load
    #   (`Sec-Fetch-Mode: navigate` and `Sec-Fetch-Dest: document`); a
    #   cross-site iframe, script, image or `fetch` gets the identity coding.
    # * No `Sec-Fetch-Site` (a client that does not send the fetch metadata
    #   headers): compress when there is no `Referer`, or when the referring
    #   page has the request's own host and port (`Host`); otherwise send
    #   the identity coding.
    #
    # The decision depends on those headers, so a response that could have
    # been compressed lists them in `Vary` (`VARY_FIELDS`).
    #
    # ```
    # request = HTTP::Request.new("GET", "/", HTTP::Headers{"Sec-Fetch-Site" => "cross-site", "Sec-Fetch-Mode" => "no-cors", "Sec-Fetch-Dest" => "image"})
    # Amber::Pipe::BreachGuard.may_compress_response_to?(request) # => false
    # ```
    module BreachGuard
      # The `Vary` field values for a response whose coding was negotiated.
      VARY_FIELDS = "Accept-Encoding, Sec-Fetch-Site, Sec-Fetch-Mode, Sec-Fetch-Dest"

      # Returns whether a response to *request* may carry a content coding.
      def self.may_compress_response_to?(request : HTTP::Request) : Bool
        headers = request.headers
        fetch_site = headers["Sec-Fetch-Site"]?
        return comes_from_own_origin_or_nowhere?(request) unless fetch_site

        case fetch_site.strip.downcase
        when "same-origin", "same-site", "none"
          true
        when "cross-site"
          header_is?(headers, "Sec-Fetch-Mode", "navigate") && header_is?(headers, "Sec-Fetch-Dest", "document")
        else
          false
        end
      end

      private def self.header_is?(headers : HTTP::Headers, name : String, expected : String) : Bool
        value = headers[name]?
        !value.nil? && value.strip.compare(expected, case_insensitive: true) == 0
      end

      # True without a `Referer`, or when the `Referer` names the same host
      # and port as the request's `Host`. The scheme is not compared: `Host`
      # does not carry one.
      private def self.comes_from_own_origin_or_nowhere?(request : HTTP::Request) : Bool
        referer = request.headers["Referer"]?
        return true unless referer

        host_field = request.headers["Host"]?
        return false unless host_field

        referer_uri = URI.parse(referer.strip)
        referer_host = referer_uri.host
        return false unless referer_host

        referer_scheme = referer_uri.scheme
        default_port = referer_scheme && referer_scheme.downcase == "http" ? 80 : 443
        referer_port = referer_uri.port || default_port
        request_host, request_port = host_and_port(host_field.strip, default_port)
        referer_host.compare(request_host, case_insensitive: true) == 0 && referer_port == request_port
      rescue URI::Error
        false
      end

      # Splits a `Host` field into host and port; a bracketed IPv6 address
      # keeps its brackets off, as `URI#host` does.
      private def self.host_and_port(host_field : String, default_port : Int32) : {String, Int32?}
        uri = URI.parse("//#{host_field}")
        host = uri.host || host_field
        {host, uri.port || default_port}
      rescue URI::Error
        {host_field, default_port}
      end
    end
  end
end
