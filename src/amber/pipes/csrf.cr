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
          unless context.session[CSRF_KEY]?.is_a? String
            context.session[CSRF_KEY] = Random::Secure.urlsafe_base64(TOKEN_LENGTH)
          end
          context.session[CSRF_KEY].as(String)
        end
      end

      module RefreshableToken
        extend self
        extend BaseToken

        def token(context) : String
          real_session_token(context)
        end

        def valid_token?(context)
          (request_token(context) == token(context)) && context.session.delete(CSRF_KEY)
        end
      end

      module PersistentToken
        extend self
        extend BaseToken

        def valid_token?(context)
          if request_token(context) && real_session_token(context)
            decoded_request = Base64.decode(request_token(context).to_s)
            return false unless decoded_request.size == TOKEN_LENGTH * 2

            unmasked = TokenOperations.unmask(decoded_request)
            session_token = Base64.decode(real_session_token(context))
            return Crypto::Subtle.constant_time_compare(unmasked, session_token)
          end
          false
        rescue Base64::Error
          false
        end

        def token(context) : String
          unmask_token = Base64.decode(real_session_token(context))
          TokenOperations.mask(unmask_token)
        end

        module TokenOperations
          extend self

          # Creates a masked version of the authenticity token that varies
          # on each request. The masking is used to mitigate SSL attacks
          # like BREACH.
          def mask(unmasked_token : Bytes) : String
            one_time_pad = Bytes.new(TOKEN_LENGTH).tap { |buf| Random::Secure.random_bytes(buf) }
            encrypted_csrf_token = xor_bytes_arrays(unmasked_token, one_time_pad)

            masked_token = IO::Memory.new
            masked_token.write(one_time_pad)
            masked_token.write(encrypted_csrf_token)
            Base64.urlsafe_encode(masked_token.to_slice)
          end

          def unmask(masked_token : Bytes) : Bytes
            one_time_pad = masked_token[0, TOKEN_LENGTH]
            encrypted_csrf_token = masked_token[TOKEN_LENGTH, TOKEN_LENGTH]
            xor_bytes_arrays(encrypted_csrf_token, one_time_pad)
          end

          def xor_bytes_arrays(token : Bytes, pad : Bytes) : Bytes
            token.map_with_index { |b, i| b ^ pad[i] }
          end
        end
      end
    end
  end
end
