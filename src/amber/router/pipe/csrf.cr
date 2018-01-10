require "random/secure"
require "crypto/subtle"

module Amber
  module Pipe
    # The CSRF Handler adds support for Cross Site Request Forgery.
    class CSRF < Base
      CHECK_METHODS = %w(PUT POST PATCH DELETE)
      HEADER_KEY    = "X-CSRF-TOKEN"
      PARAM_KEY     = "_csrf"
      CSRF_KEY      = "csrf.token"
      TOKEN_LENGTH  = 32

      class_property token_strategy : PersistentToken | RefreshableToken = PersistentToken

      def call(context : HTTP::Server::Context)
        if valid_http_method?(context) || self.class.token_strategy.valid_token?(context)
          call_next(context)
        else
          raise Amber::Exceptions::Forbidden.new("CSRF check failed.")
        end
      end

      def valid_http_method?(context)
        !CHECK_METHODS.includes?(context.request.method)
      end

      def self.token(context)
        token_strategy.token(context)
      end

      def self.tag(context)
        %Q(<input type="hidden" name="#{PARAM_KEY}" value="#{token(context)}" />)
      end

      def self.metatag(context)
        %Q(<meta name="#{PARAM_KEY}" content="#{token(context)}" />)
      end

      module BaseToken
        def request_token(context)
          context.params[PARAM_KEY]? || context.request.headers[HEADER_KEY]?
        end

        def real_session_token(context) : String
          (context.session[CSRF_KEY] ||= Random::Secure.urlsafe_base64(TOKEN_LENGTH)).to_s
        end
      end

      module RefreshableToken
        extend self
        extend BaseToken

        def token(context) : String
          real_session_token(context)
        end

        def valid_token?(context)
          request_token = request_token(context)

          request_token &&
            Crypto::Subtle.constant_time_compare(request_token, token(context)) &&
            !!context.session.delete(CSRF_KEY)
        end
      end

      module PersistentToken
        extend self
        extend BaseToken

        def valid_token?(context)
          request_token = request_token(context)
          return false if request_token.nil?
          decoded_request_token = Base64.decode_string(request_token)
          return false if decoded_request_token.bytesize != 2 * TOKEN_LENGTH
          unmaseked_request_token = TokenOperations.unmask(decoded_request_token)
          decoded_session_token = Base64.decode_string(real_session_token(context))

          Crypto::Subtle.constant_time_compare(unmaseked_request_token, decoded_session_token)
        end

        def token(context) : String
          unmask_token = Base64.decode_string(real_session_token(context))
          masked_token = TokenOperations.mask(unmask_token)
          Base64.urlsafe_encode(masked_token)
        end

        module TokenOperations
          extend self

          # Creates a masked version of the authenticity token that varies
          # on each request. The masking is used to mitigate SSL attacks
          # like BREACH.
          def mask(unmasked_token)
            one_time_pad = Bytes.new(TOKEN_LENGTH).tap { |buf| Random::Secure.random_bytes(buf) }
            encrypted_csrf_token = xor_byte_strings(one_time_pad, unmasked_token.bytes)
            "#{String.new(one_time_pad)}#{encrypted_csrf_token}"
          end

          def unmask(masked_token)
            one_time_pad = masked_token.bytes[0...TOKEN_LENGTH]
            encrypted_csrf_token = masked_token.bytes[TOKEN_LENGTH..-1]
            xor_byte_strings(one_time_pad, encrypted_csrf_token)
          end

          def xor_byte_strings(s1, s2) : String
            s1.each_with_index { |c1, i| s2[i] ^= c1 }
            String.new(s2.to_unsafe, TOKEN_LENGTH)
          end
        end
      end
    end
  end
end
