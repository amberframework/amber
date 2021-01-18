require "./*"
require "http"

module Amber::Router::Cookies
  class Store
    include Enumerable(String)

    getter cookies
    getter secret : String
    property host : String?
    property secure : Bool = false

    def initialize(@host = nil, @secret = Random::Secure.urlsafe_base64(32), @secure = false)
      @cookies = {} of String => String
      @set_cookies = {} of String => HTTP::Cookie
      @delete_cookies = {} of String => HTTP::Cookie
    end

    def self.from_headers(headers)
      cookies = {} of String => HTTP::Cookie
      if values = headers.get?("Cookie")
        values.each do |header|
          HTTP::Cookie::Parser.parse_cookies(header) do |cookie|
            cookies[cookie.name] = cookie
          end
        end
      end

      if values = headers.get?("Set-Cookie")
        values.each do |header|
          HTTP::Cookie::Parser.parse_cookies(header) do |cookie|
            cookies[cookie.name] = cookie
          end
        end
      end

      cookies
    end

    def self.build(request, secret)
      headers = request.headers
      host = {% if compare_versions(Crystal::VERSION, "0.36.0-0") >= 0 %}
               request.hostname
             {% else %}
               request.host
             {% end %}
      secure = (headers["HTTPS"]? == "on")
      new(host, secret, secure).tap do |store|
        store.update(from_headers(headers))
      end
    end

    def permanent
      @permanent ||= PermanentStore.new(self)
    end

    def encrypted
      @encrypted ||= EncryptedStore.new(self, @secret)
    end

    def signed
      @signed ||= SignedStore.new(self, @secret)
    end

    def update(cookies)
      cookies.each do |name, cookie|
        @cookies[name] = cookie.value
      end
    end

    def each(&block : T -> _)
      @cookies.values.each do |cookie|
        yield cookie
      end
    end

    def each
      @cookies.each_value
    end

    def [](name)
      get(name)
    end

    def get(name)
      @cookies[name]?
    end

    def set(name : String, value : String, path : String = "/",
            expires : Time? = nil, domain : String? = nil,
            secure : Bool = false, http_only : Bool = false,
            extension : String? = nil)
      if @cookies[name]? != value || expires
        @cookies[name] = value
        @set_cookies[name] = HTTP::Cookie.new(name, value, path, expires, domain, secure, http_only, extension)
        @delete_cookies.delete(name) if @delete_cookies.has_key?(name)
      end
    end

    def delete(name : String, path = "/", domain : String? = nil)
      return unless @cookies.has_key?(name)

      value = @cookies.delete(name)
      @delete_cookies[name] = HTTP::Cookie.new(name, "", path, ::Time.unix(0), domain)
      value
    end

    def deleted?(name)
      @delete_cookies.has_key?(name)
    end

    def []=(name, value)
      set(name, value)
    end

    def []=(name, cookie : HTTP::Cookie)
      @cookies[name] = cookie.value
      @set_cookies[name] = cookie
    end

    def write(headers)
      cookies = [] of String
      @set_cookies.each { |_, cookie| cookies << cookie.to_set_cookie_header if write_cookie?(cookie) }
      @delete_cookies.each { |_, cookie| cookies << cookie.to_set_cookie_header }
      headers.add("Set-Cookie", cookies)
    end

    def write_cookie?(cookie)
      @secure || !cookie.secure
    end
  end
end
