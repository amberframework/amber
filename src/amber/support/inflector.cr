require "./text_matching"

module Amber
  module Support
    module Inflector
      # Converts a plural English word to its singular form.
      # Handles common English plural patterns. For edge cases,
      # developers can override with the explicit `as:` parameter.
      def self.singularize(word : String) : String
        return word if word.empty?

        # Handle common irregular plurals
        if irregular = IRREGULARS[word.downcase]?
          return irregular
        end

        # Apply rules in order (most specific first)
        SINGULAR_RULES.each do |rule|
          return rule.apply(word) if rule.applies_to?(word)
        end

        word
      end

      # Converts a singular English word to a simple prefix-friendly form.
      # Used to generate route name prefixes from namespace paths.
      # Strips leading/trailing slashes and replaces inner slashes with underscores.
      def self.namespace_to_prefix(namespace : String) : String
        namespace.strip('/').gsub('/', '_').gsub('-', '_')
      end

      IRREGULARS = {
        "people"   => "person",
        "men"      => "man",
        "women"    => "woman",
        "children" => "child",
        "mice"     => "mouse",
        "geese"    => "goose",
        "teeth"    => "tooth",
        "feet"     => "foot",
        "data"     => "datum",
        "criteria" => "criterion",
        "media"    => "medium",
        "analyses" => "analysis",
        "oxen"     => "ox",
      }

      # A suffix rule: a word that ends in `suffix` (in any case), after a
      # character that `preceding` allows, swaps that suffix for
      # `replacement`.
      struct SingularRule
        # Which character may stand just before the suffix.
        enum Preceding
          Anything
          Vowel
          AnythingButS
        end

        getter suffix : String
        getter replacement : String
        getter preceding : Preceding

        def initialize(@suffix : String, @replacement : String, @preceding : Preceding = Preceding::Anything)
        end

        def applies_to?(word : String) : Bool
          return false unless TextMatching.ends_with_ignoring_case?(word, suffix)
          return true if preceding.anything?

          before_index = word.size - suffix.size - 1
          return false if before_index < 0
          before = word.char_at(before_index)
          if preceding.vowel?
            "aeiou".each_char.any? { |vowel| TextMatching.same_ignoring_case?(before, vowel) }
          else
            !TextMatching.same_ignoring_case?(before, 's')
          end
        end

        # Returns *word* with its suffix replaced; call it only when
        # `applies_to?` holds.
        def apply(word : String) : String
          word[0, word.size - suffix.size] + replacement
        end
      end

      # Rules ordered from most specific to least specific
      SINGULAR_RULES = [
        SingularRule.new("ies", "y"),                                         # categories -> category,eries -> ery
        SingularRule.new("ves", "fe"),                                        # wives -> wife, knives -> knife
        SingularRule.new("ses", "se", SingularRule::Preceding::Vowel),        # cases -> case, databases -> database
        SingularRule.new("sses", "ss"),                                       # addresses -> address, dresses -> dress
        SingularRule.new("ses", "se", SingularRule::Preceding::AnythingButS), # responses -> response
        SingularRule.new("xes", "x"),                                         # boxes -> box, indexes -> index
        SingularRule.new("zes", "ze"),                                        # freezes -> freeze
        SingularRule.new("ches", "ch"),                                       # matches -> match, batches -> batch
        SingularRule.new("shes", "sh"),                                       # dishes -> dish, crashes -> crash
        SingularRule.new("s", ""),                                            # users -> user, posts -> post (most common)
      ]
    end
  end
end
