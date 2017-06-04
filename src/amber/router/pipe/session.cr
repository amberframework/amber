require "http/cookie"
require "base64"
require "yaml"
require "openssl/hmac"

module Amber
  module Pipe
    # The session handler provides a cookie based session.  The handler will
    # encode and decode the cookie and provide the hash in the context that can
    # be used to maintain data across requests.
    class Session < Base
      property :key
      property secret : String

      def self.instance
        @@instance ||= new
      end

      def initialize
        @key = "#{Server.settings.project_name}.session"
        @secret = Server.settings.secret
      end

      def call(context : HTTP::Server::Context)
        cookies = context.request.cookies
        decode(context.session, cookies[@key].value) if cookies.has_key?(@key)
        call_next(context)
        value = encode(context.session)
        cookies = context.response.cookies
        cookies << HTTP::Cookie.new(@key, value)
        cookies.add_response_headers(context.response.headers)
        context
      end

      private def decode(session, data)
        sha1, data = data.split("--", 2)
        if sha1 == OpenSSL::HMAC.hexdigest(:sha1, @secret, data)
          values = YAML.parse(Base64.decode_string(data))
          values.each do |key, value|
            session[key.to_s] = value.to_s
          end
        end
      end

      private def encode(session)
        data = Base64.encode(session.to_yaml)
        sha1 = OpenSSL::HMAC.hexdigest(:sha1, @secret, data)
        "#{sha1}--#{data}"
      end
    end
  end

  module Router
    module Session
      # clear the session.  You can call this to logout a user.
      def clear_session
        @session = Hash.new 
      end

      # Holds a hash of session variables.  This can be used to hold data between
      # sessions.  It's recommended to avoid holding any private data in the
      # session since this is held in a cookie.  Also avoid putting more than 4k
      # worth of data in the session to avoid slow pageload times.
      def session
        @session ||= Hash.new 
      end

      class Hash < Hash(String, String)
        def []=(key : String | Symbol, value : V)
          super(key.to_s, value)
        end

        def [](key : Symbol | String)
          key = key.to_s
          @read << key
          fetch(key, nil)
        end
      end
    end
  end
end
