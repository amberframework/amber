module Amber
  module Pipe
    class Flash < Base
      PARAM_KEY = "_flash"

      def call(context)
        call_next(context)
      ensure
        session = context.session
        flash = context.flash.not_nil!
        session[PARAM_KEY] = flash.to_session
      end
    end
  end
end
