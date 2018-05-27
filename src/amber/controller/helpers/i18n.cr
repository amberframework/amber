module Amber::Controller::Helpers
  module I18n
    def t(*arg)
      ::I18n.translate(*arg, force_locale: context.locale)
    end

    def l(*arg)
      ::I18n.localize(*arg, force_locale: context.locale)
    end
  end
end
