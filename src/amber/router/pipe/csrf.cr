require "random/secure"

module Amber
  module Pipe
    # The CSRF Handler adds support for Cross Site Request Forgery.
    class CSRF < Base
      CHECK_METHODS = %w(PUT POST PATCH DELETE)
      HEADER_KEY    = "X-CSRF-TOKEN"
      PARAM_KEY     = "_csrf"
      CSRF_KEY      = "csrf.token"

      def call(context : HTTP::Server::Context)
        if valid_http_method?(context) || valid_token?(context)
          context.session.delete(CSRF_KEY)
          call_next(context)
        else
          raise Amber::Exceptions::Forbidden.new("CSRF check failed.")
        end
      end

      def valid_http_method?(context)
        !CHECK_METHODS.includes?(context.request.method)
      end

      def valid_token?(context)
        (context.params[PARAM_KEY]? || context.request.headers[HEADER_KEY]?) == self.class.token(context)
      end

      def self.token(context)
        context.session[CSRF_KEY] ||= Random::Secure.urlsafe_base64(32)
      end

      def self.tag(context)
        %Q(<input type="hidden" name="#{PARAM_KEY}" value="#{token(context)}" />)
      end

      def self.metatag(context)
        %Q(<meta name="#{HEADER_KEY}" content="#{token(context)}" />)
      end
    end
  end
end
