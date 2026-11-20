module Amber
  module Pipe
    # Carries the flash from one request to the next through the session.
    #
    # The session is written only when the flash has messages to carry, or
    # when the session still holds a flash that is now empty and must be
    # cleared. A request that never sets a flash leaves the session unchanged,
    # so a visitor without a session cookie is given no session.
    class Flash < Base
      PARAM_KEY = "_flash"

      # The session form of a flash with no messages.
      EMPTY_FLASH_JSON = "{}"

      def call(context)
        call_next(context)
      ensure
        carry_flash_to_next_request(context)
      end

      private def carry_flash_to_next_request(context : HTTP::Server::Context) : Nil
        session = context.session
        flash_json = context.flash.to_session

        if flash_json == EMPTY_FLASH_JSON
          session.delete(PARAM_KEY) if session.has_key?(PARAM_KEY)
        elsif session[PARAM_KEY]? != flash_json
          session[PARAM_KEY] = flash_json
        end
      end
    end
  end
end
