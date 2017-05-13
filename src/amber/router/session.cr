module Amber::Router
  module Session
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
  end
end