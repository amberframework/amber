module Amber::Pipe
  # Some HTTP proxies do not support arbitrary HTTP methods or newer HTTP methods
  # (such as PATCH). In that case it’s possible to “proxy” HTTP methods through the
  class Method < Base
    METHOD           = "_method"
    OVERRIDE_HEADER  = "X-HTTP-Method-Override"
    OVERRIDE_METHODS = %w(PATCH PUT DELETE)

    def call(context : HTTP::Server::Context)
      override_request_method!(context)
      call_next(context)
      context
    end

    private def override_request_method!(context)
      return unless %(GET POST).includes? context.request.method
      method = context.params[METHOD]? || context.request.headers[OVERRIDE_HEADER]?
      context.request.method = method if method && OVERRIDE_METHODS.includes? method
    end
  end
end
