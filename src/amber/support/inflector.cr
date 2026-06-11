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
        SINGULAR_RULES.each do |pattern, replacement|
          if word.matches?(pattern)
            return word.sub(pattern, replacement)
          end
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

      # Rules ordered from most specific to least specific
      SINGULAR_RULES = [
        {/ies\z/i, "y"},              # categories -> category,eries -> ery
        {/ves\z/i, "fe"},             # wives -> wife, knives -> knife
        {/([aeiou])ses\z/i, "\\1se"}, # cases -> case, databases -> database
        {/sses\z/i, "ss"},            # addresses -> address, dresses -> dress
        {/([^s])ses\z/i, "\\1se"},    # responses -> response
        {/xes\z/i, "x"},              # boxes -> box, indexes -> index
        {/zes\z/i, "ze"},             # freezes -> freeze
        {/ches\z/i, "ch"},            # matches -> match, batches -> batch
        {/shes\z/i, "sh"},            # dishes -> dish, crashes -> crash
        {/s\z/i, ""},                 # users -> user, posts -> post (most common)
      ]
    end
  end
end
