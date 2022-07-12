module Amber::Controller::Helpers
  module I18n
    def t(*arg)
      # removed the param forced_locale because it was requiring the `context.locale` which then doesn't compile
      # TODO add a way to specify the locale from the URL
      ::I18n.translate(*arg)
    end

    def l(*arg)
      # removed the param forced_locale because it was requiring the `context.locale` which then doesn't compile
      # TODO add a way to specify the locale from the URL
      ::I18n.localize(*arg)
    end
  end
end
