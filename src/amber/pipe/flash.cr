require "base64"
require "json"
require "openssl/hmac"

module Amber
  module Pipe
    # The flash handler provides a mechanism to pass flash message between
    # requests.
    class Flash < Base
      property :key

      def self.instance
        @@instance ||= new
      end

      def initialize
        @key = "amber.flash"
      end

      def call(context : HTTP::Server::Context)
        cookies = context.request.cookies
        decode(context.flash, cookies[@key].value) if cookies.has_key?(@key)
        call_next(context)
        value = encode(context.flash.unread)
        cookies = context.response.cookies
        cookies << HTTP::Cookie.new(@key, value)
        cookies.add_response_headers(context.response.headers)
        context
      end

      private def decode(flash, data)
        json = Base64.decode_string(data)
        values = JSON.parse(json)
        values.each do |key, value|
          flash[key.to_s] = value.to_s
        end
      end

      private def encode(flash)
        data = Base64.encode(flash.to_json)
        return data
      end
    end
  end
end
