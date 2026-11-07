module Amber
  module Support
    # :nodoc:
    #
    # Character tests and scans that Amber's own String code shares, so a
    # fixed job (a suffix rule, a tag strip, a whitespace run) needs no regex
    # engine. Each test reproduces what the PCRE2 class it replaced matched
    # under Crystal's default `Regex` options (UTF and UCP), as far as the
    # stdlib's Unicode tables reach.
    module TextMatching
      # Connector punctuation (Unicode category Pc). PCRE2 counts it as a
      # word character under UCP; the stdlib has no predicate for it. The set
      # has not changed since Unicode 4.1.
      CONNECTOR_PUNCTUATION = {'_', '‿', '⁀', '⁔', '︳', '︴', '﹍', '﹎', '﹏', '＿'}

      # Returns `true` when *char* is a word character as `\w` judged it: a
      # letter, a number, a combining mark or connector punctuation.
      #
      # PCRE2 counts only non-spacing marks (Mn); the stdlib can test marks
      # only as a whole, so spacing and enclosing marks (Mc, Me) count here too.
      def self.word_character?(char : Char) : Bool
        char.alphanumeric? || char.mark? || CONNECTOR_PUNCTUATION.includes?(char)
      end

      # Returns `true` when *char* is whitespace as `\s` judged it: the stdlib's
      # whitespace plus NEL (U+0085) and the Mongolian vowel separator
      # (U+180E), which PCRE2 also counts.
      def self.whitespace?(char : Char) : Bool
        char.whitespace? || char == '\u0085' || char == '᠎'
      end

      # Returns `true` when *left* and *right* are the same letter ignoring
      # case, as a case-insensitive (`/i`) pattern compared them: by simple
      # case folding, so `'ſ'` matches `'s'` and `'K'` (Kelvin) matches `'k'`.
      # A dotted capital I (U+0130) matches only itself, as in PCRE2.
      def self.same_ignoring_case?(left : Char, right : Char) : Bool
        left == right || case_key(left) == case_key(right)
      end

      # Returns the character indexes in *text_chars* where *phrase_chars*
      # starts, ignoring case, scanning left to right without overlaps (the
      # matches `gsub` would replace). Runs in time linear in both sizes.
      # *phrase_chars* must not be empty.
      def self.match_starts_ignoring_case(text_chars : Array(Char), phrase_chars : Array(Char)) : Array(Int32)
        phrase_keys = phrase_chars.map { |char| case_key(char) }
        fallback = partial_match_table(phrase_keys)
        list_of_starts = [] of Int32
        matched = 0
        text_chars.each_with_index do |char, index|
          key = case_key(char)
          while matched > 0 && phrase_keys[matched] != key
            matched = fallback[matched - 1]
          end
          matched += 1 if phrase_keys[matched] == key
          if matched == phrase_keys.size
            list_of_starts << index - matched + 1
            # Start over after a match so the next one cannot overlap it.
            matched = 0
          end
        end
        list_of_starts
      end

      # Knuth-Morris-Pratt table: for each prefix of *keys*, the length of its
      # longest proper prefix that is also its suffix.
      private def self.partial_match_table(keys : Array(Char)) : Array(Int32)
        table = Array.new(keys.size, 0)
        length = 0
        (1...keys.size).each do |index|
          while length > 0 && keys[index] != keys[length]
            length = table[length - 1]
          end
          length += 1 if keys[index] == keys[length]
          table[index] = length
        end
        table
      end

      # Returns `true` when *text* ends with *suffix*, comparing each
      # character with `same_ignoring_case?`.
      def self.ends_with_ignoring_case?(text : String, suffix : String) : Bool
        text_size = text.size
        suffix_size = suffix.size
        return false if suffix_size > text_size
        matches_ignoring_case_at?(text, text_size - suffix_size, suffix)
      end

      # Returns `true` when *text* starts with *prefix*, comparing each
      # character with `same_ignoring_case?`.
      def self.starts_with_ignoring_case?(text : String, prefix : String) : Bool
        return false if prefix.size > text.size
        matches_ignoring_case_at?(text, 0, prefix)
      end

      # Returns `true` when the characters of *text* from character index
      # *start* on spell *expected*, ignoring case.
      def self.matches_ignoring_case_at?(text : String, start : Int32, expected : String) : Bool
        expected_size = expected.size
        return false if start < 0 || start + expected_size > text.size

        expected.each_char_with_index do |expected_char, offset|
          return false unless same_ignoring_case?(text.char_at(start + offset), expected_char)
        end
        true
      end

      # Returns *text* with every span from a `<` to the next `>` removed,
      # both included. A `<` with no `>` after it stays, with the rest of
      # the text.
      def self.remove_tags(text : String) : String
        return text unless text.includes?('<')

        String.build(text.bytesize) do |io|
          offset = 0
          while opening = text.byte_index('<', offset)
            closing = text.byte_index('>', opening)
            break unless closing
            io.write(text.to_slice[offset, opening - offset])
            offset = closing + 1
          end
          io.write(text.to_slice[offset, text.bytesize - offset])
        end
      end

      private def self.case_key(char : Char) : Char
        return char if char == 'İ'
        char.downcase.downcase(Unicode::CaseOptions::Fold)
      end
    end
  end
end
