require "../dsl/*"

module Amber::Controller
  module Callbacks
    macro included
      include Amber::DSL::Callbacks
      property filters : Filters = Filters.new

      # TODO: Find a way to make these protected again.
      def run_before_filter(action)
        if self.responds_to? :before_filters
          self.before_filters
          @filters.run(:before, :all)
          @filters.run(:before, :except, action)
          @filters.run(:before, action)
        end
      end

      def run_after_filter(action)
        if self.responds_to? :after_filters
          self.after_filters
          @filters.run(:after, action)
          @filters.run(:after, :except, action)
          @filters.run(:after, :all)
        end
      end
    end
  end

  record Filter, precedence : Symbol, action : Symbol, blk : -> Nil, excepts : Array(Symbol) = [] of Symbol do
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

    def except(action : Symbol, &block : -> Nil)
      filters.add Filter.new(precedence, :except, block, [action])
    end

    def except(actions : Array(Symbol), &block : -> Nil)
      filters.add Filter.new(precedence, :except, block, actions)
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

    def each(&block : {Symbol, Array(Filter)} -> _)
      filters.each do |key, filter|
        yield({key, filter})
      end
    end

    def run(precedence : Symbol, action : Symbol, except_action : Symbol | Nil = nil)
      filters[precedence].each do |filter|
        next if except_filter_and_has_action?(filter, except_action)
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

    private def except_filter_and_has_action?(filter : Filter, except_action : Symbol | Nil)
      filter.action == :except && filter.excepts.includes?(except_action)
    end
  end
end
