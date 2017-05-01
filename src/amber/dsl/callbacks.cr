module Amber::DSL
  module Callbacks
    macro before_action
      protected def before_filters
        filters.register :before { {{yield}} }
      end
    end

    macro after_action
      protected def after_filters
        filters.register :after { {{yield}} }
      end
    end
  end
end
