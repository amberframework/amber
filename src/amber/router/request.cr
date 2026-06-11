require "./params"
require "./router"
require "./route"

class HTTP::Request
  METHOD          = "_method"
  OVERRIDE_HEADER = "X-HTTP-Method-Override"

  # Required for the `matched_route` method
  @matched_route : Amber::Router::RoutedResult(Amber::Route)?

  # Required for the `params` method
  @params : Amber::Router::Params?

  # A necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  def params
    @params ||= Amber::Router::Params.new(self)
  end

  # This is a necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  def port
    parsed_uri.port
  end

  # This is a necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  def url
    parsed_uri.to_s
  end

  private def parsed_uri
    if resource.starts_with?("http://") || resource.starts_with?("https://")
      URI.parse(resource)
    else
      uri
    end
  end

  # This is a necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  def route
    matched_route.payload.not_nil!
  end

  # This is a necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  def valid_route?
    matched_route.payload? || router.socket_route_defined?(self)
  end

  # This is a necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  def process_websocket
    router.get_socket_handler(self)
  end

  # This is a necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  def matched_route
    @matched_route ||= router.match_by_request(self)
  end

  # This is a necessary method that the rest of the Amber server requires to be present
  # TODO: Refactor this into a different approach that doesn't require monkey patching the std lib
  private def router
    Amber::Server.router
  end
end
