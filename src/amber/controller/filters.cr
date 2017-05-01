module Amber::Controller

  module Callbacks
    macro included
      include Amber::DSL::Callbacks
      protected property filters : Callbacks = Callbacks.new

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
  record FilterBuilder, filters : Filters, precedence : Symbol do
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

  class Filters
    property filters = {} of Symbol => Array(Filter)

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
