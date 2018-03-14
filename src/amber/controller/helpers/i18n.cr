module Amber::Controller::Helpers
  module I18n
    def t(*arg)
      ::I18n.translate(*arg)
    end

    def l(*arg)
      ::I18n.localize(*arg)
    end
  end
end
