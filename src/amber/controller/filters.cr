module Amber::Controller

  module FilterHelper
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

      protected def run_actions(precedence : Symbol, action : Symbol)

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


  record Filter, precedence :  Symbol, action : Symbol, blk : ->String | Nil do
  end


  # Builds a BeforeAction filter.
  #
  # The yielded object has an `add` method that accepts two arguments,
  # a key (`Symbol`) and a block ->(`String` or `Nil`).
  #
  # ```
  # FilterChainBuilder.build do |b|
  #   filter :index, :show { some_method }
  #   filter :delete { }
  # end
  # ```
  record FilterBuilder, callbacks : Callbacks, precedence : Symbol do
    def only(action : Symbol, &blk : ->String | Nil )
      add(action, blk
    end

    def only(actions : Array(Symbol), &block : ->String | Nil)
      actions.each { |action| add(action, blk) }
    end

    def add(action, block : ->String | Nil)
      callbacks.add Filter.new(precedence, action, block)
    end
  end

  class Callbacks
    property filters = {} of Symbol => Array(Filter)
    # include Enumerable(Symbol, Array(Filter))

    def register(precedence : Symbol)
      with FilterBuilder.new(self, precedence) yield
    end

    def add(filter : Filter)
      filters[filter.precedence] ||= [] of Filter
      filters[filter.precedence] << filter
    end

    def run(precedence : Symbol, action : Symbol)
      filters[precedence].each do |filter|
        filter.blk.call if filter.action == action
      end
    end
  end
end
