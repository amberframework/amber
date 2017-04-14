#The Context holds the request and the response objects.  The context is
#passed to each handler that will read from the request object and build a
#response object.  Params and Session hash can be accessed from the Context.
class HTTP::Server::Context
  alias ParamTypes = Nil | String | Int64 | Float64 | Bool | Hash(String, JSON::Type) | Array(JSON::Type)

  # clear the params.
  def clear_params
    @params = HTTP::Params.new({} of String => Array(String))
  end

  # params hold all the parameters that may be passed in a request.  The
  # parameters come from either the url or the body via json or form posts.
  def params
    @params ||= HTTP::Params.new({} of String => Array(String))
  end

  # clear the session.  You can call this to logout a user.
  def clear_session
    @session = {} of String => String
  end

  # Holds a hash of session variables.  This can be used to hold data between
  # sessions.  It's recommended to avoid holding any private data in the
  # session since this is held in a cookie.  Also avoid putting more than 4k
  # worth of data in the session to avoid slow pageload times.
  def session
    @session ||= {} of String => String
  end

  # clear the flash messages.
  def clear_flash
    @flash = FlashHash.new
  end

  # Holds a hash of flash variables.  This can be used to hold data between
  # requests. Once a flash message is read, it is marked for removal.
  def flash
    @flash ||= FlashHash.new
  end

  # A hash that keeps track if its been accessed
  class FlashHash < Hash(String, String)

    def initialize
      @read = [] of String
      super
    end

    def fetch(key)
      @read << key
      super
    end

    def each
      current = @first
      while current
        yield({current.key, current.value})
        @read << current.key
        current = current.fore
      end
      self
    end

    def unread
      reject {|key,_| @read.includes? key}
    end
  end
end