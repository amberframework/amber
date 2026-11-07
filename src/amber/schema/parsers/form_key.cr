module Amber::Schema::Parser
  # The shapes of form keys and form values, read byte by byte in one pass.
  module FormKey
    # Splits `user[tags][0]` into `["user", "tags", "0"]`.
    def self.segments(key : String) : Array(String)
      list_of_segments = [] of String
      segment_start = 0

      key.each_byte.with_index do |byte, byte_index|
        next unless byte === '[' || byte === ']'

        list_of_segments << key.byte_slice(segment_start, byte_index - segment_start) if byte_index > segment_start
        segment_start = byte_index + 1
      end

      list_of_segments << key.byte_slice(segment_start) if segment_start < key.bytesize
      list_of_segments
    end

    # Splits `tags[12]` into `{"tags", "12"}`. Returns nil for any other shape.
    def self.indexed_name_and_index(key : String) : Tuple(String, String)?
      return nil unless key.ends_with?(']')

      opening_bracket_index = key.to_slice.rindex('['.ord.to_u8)
      return nil if opening_bracket_index.nil? || opening_bracket_index.zero?

      index_text = key.byte_slice(opening_bracket_index + 1, key.bytesize - opening_bracket_index - 2)
      return nil unless digits?(index_text)

      {key.byte_slice(0, opening_bracket_index), index_text}
    end

    # True when *text* is one or more ASCII digits.
    def self.digits?(text : String) : Bool
      !text.empty? && text.each_char.all?(&.ascii_number?)
    end

    # True for an optional minus sign followed by digits.
    def self.integer?(text : String) : Bool
      digits?(text.starts_with?('-') ? text.byte_slice(1) : text)
    end

    # True for `-1`, `1.5`, `.5` and `2e10`: an optional minus sign, an optional
    # whole part, an optional dot, required digits, and an optional exponent.
    def self.decimal?(text : String) : Bool
      mantissa = text.starts_with?('-') ? text.byte_slice(1) : text

      if exponent_index = mantissa.byte_index('e') || mantissa.byte_index('E')
        exponent = mantissa.byte_slice(exponent_index + 1)
        exponent = exponent.byte_slice(1) if exponent.starts_with?('+') || exponent.starts_with?('-')
        return false unless digits?(exponent)

        mantissa = mantissa.byte_slice(0, exponent_index)
      end

      if dot_index = mantissa.byte_index('.')
        whole_part = mantissa.byte_slice(0, dot_index)
        fraction = mantissa.byte_slice(dot_index + 1)
        (whole_part.empty? || digits?(whole_part)) && digits?(fraction)
      else
        digits?(mantissa)
      end
    end
  end
end
