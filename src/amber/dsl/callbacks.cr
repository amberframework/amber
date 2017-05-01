module Amber::DSL
  module Callbacks
    macro before_action
      def before_filters : Nil
        filters.register :before do
          {{yield}}
        end
      end
    end

    macro after_action
      def after_filters : Nil
        filters.register :after do
          {{yield}}
        end
      end
    end
  end
end
