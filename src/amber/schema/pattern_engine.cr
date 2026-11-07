module Amber::Schema
  # Runs the string patterns a schema declares with `pattern:`, `filename_pattern:`
  # or a custom `format:`.
  #
  # The `field` macro calls `use_regex` for a field that declares one, so only those
  # applications compile `Regex` and link a regex engine.
  module PatternEngine
    class MissingEngineError < Exception
    end

    @@matcher : Proc(String, String, Bool)?

    def self.use_regex : Nil
      @@matcher = ->(pattern : String, text : String) { text.matches?(Regex.new(pattern)) }
    end

    def self.matches?(pattern : String, text : String) : Bool
      matcher = @@matcher
      unless matcher
        raise MissingEngineError.new(
          "A schema pattern needs the regex engine. Declare it with the `field` macro, or call Amber::Schema::PatternEngine.use_regex at boot."
        )
      end

      matcher.call(pattern, text)
    end
  end
end
