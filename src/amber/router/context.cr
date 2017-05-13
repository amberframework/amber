require "tempfile"
require "./*"
# The Context holds the request and the response objects.  The context is
# passed to each handler that will read from the request object and build a
# response object.  Params and Session hash can be accessed from the Context.
class HTTP::Server::Context
  include Amber::Router::Files
  include Amber::Router::Session
  include Amber::Router::Flash
  include Amber::Router::Params

  property route : Radix::Result(Amber::Route)

  def initialize(@request : HTTP::Request, @response : HTTP::Server::Response)
    router = Amber::Router::Router.instance
    @route = router.match_by_request(@request)
    parse_params
    upgrade_request_method!
  end
end
