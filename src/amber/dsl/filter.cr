module Amber::DSL
  module Filter
    macro included
      protected property filters : Callbacks = Callbacks.new

      macro before_action
        protected def before_filters
          filters.register :before do
            {{yield}}
          end
        end
      end

      macro after_action
        protected def after_filters
          filters.register :after do
            {{yield}}
          end
        end
      end

      protected def run_filter(precedence : Symbol, action : Symbol)

        case precedence
        when :before
          before_filters
        when :after
          after_filters
        end

        @filters.run(precedence, action)
      end
    end
  end
end
