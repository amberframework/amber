require "../dsl/*"
module Amber::Controller
  module Callbacks
    macro included
      include Amber::DSL::Callbacks
       property filters : Filters = Filters.new
       #TODO: Find a way to make these protected again.
       def run_before_filter(action)
        if self.responds_to? :before_filters
          self.before_filters
          @filters.run(:before, action)
          @filters.run(:before, :all)
        end
      end

       def run_after_filter(action)
        if self.responds_to? :after_filters
          self.after_filters
          @filters.run(:after, action)
          @filters.run(:after, :all)
        end
      end
    end
  end

  record Filter, precedence : Symbol, action : Symbol, blk : -> Nil do
  end

  # Builds a BeforeAction filter.
  #
  # The yielded object has an `only` method that accepts two arguments,
  # a key (`Symbol`) and a block ->`Nil`.
  #
  # ```
  # FilterChainBuilder.build do |b|
  #   filter :index, :show { some_method }
  #   filter :delete { }
  # end
  # ```
  record FilterBuilder, filters : Filters, precedence : Symbol do
    def only(action : Symbol, &block : -> Nil)
      add(action, &block)
    end

    def only(actions : Array(Symbol), &block : -> Nil)
      actions.each { |action| add(action, &block) }
    end

    def all(&block : -> Nil)
      filters.add Filter.new(precedence, :all, block)
    end

    def add(action, &block : -> Nil)
      filters.add Filter.new(precedence, action, block)
    end
  end

  class Filters
    include Enumerable({Symbol, Array(Filter)})

    property filters = {} of Symbol => Array(Filter)

    def register(precedence : Symbol) : Nil
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

    def [](name)
      filters[name]
    end

    def []?(name)
      fetch(name) { nil }
    end

    def fetch(name)
      filters.fetch(name)
    end
  end
end
