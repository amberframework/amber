module Amber::Controller::Helpers
  module NumberHelpers
    # Formats a number with a delimiter for readability.
    #
    # ```
    # number_with_delimiter(1234567)                 # => "1,234,567"
    # number_with_delimiter(1234.5)                  # => "1,234.5"
    # number_with_delimiter(1234567, delimiter: ".") # => "1.234.567"
    # ```
    def number_with_delimiter(number : Number, delimiter : String = ",") : String
      str = number.to_s
      parts = str.split(".")
      integer_part = parts[0]

      negative = integer_part.starts_with?("-")
      digits = negative ? integer_part[1..] : integer_part

      formatted = group_digits(digits, delimiter)

      result = negative ? "-#{formatted}" : formatted

      if parts.size > 1
        result + "." + parts[1]
      else
        result
      end
    end

    # Formats a number as a currency string.
    #
    # ```
    # number_to_currency(1234.5)                 # => "$1,234.50"
    # number_to_currency(1234.5, unit: "EUR")    # => "EUR1,234.50"
    # number_to_currency(1234.567, precision: 3) # => "$1,234.567"
    # ```
    def number_to_currency(number : Number, unit : String = "$", precision : Int32 = 2) : String
      formatted = sprintf("%.#{precision}f", number)
      parts = formatted.split(".")
      integer_part = parts[0]

      negative = integer_part.starts_with?("-")
      digits = negative ? integer_part[1..] : integer_part

      delimited = group_digits(digits, ",")

      result = if parts.size > 1
                 "#{delimited}.#{parts[1]}"
               else
                 delimited
               end

      if negative
        "-#{unit}#{result}"
      else
        "#{unit}#{result}"
      end
    end

    # Formats a number as a percentage string.
    #
    # ```
    # number_to_percentage(75.5)                 # => "75.5%"
    # number_to_percentage(75.567, precision: 2) # => "75.57%"
    # ```
    def number_to_percentage(number : Number, precision : Int32 = 1) : String
      sprintf("%.#{precision}f%%", number)
    end

    # Formats a byte count into a human-readable file size.
    #
    # ```
    # number_to_human_size(1024)    # => "1.00 KB"
    # number_to_human_size(1048576) # => "1.00 MB"
    # number_to_human_size(500)     # => "500 Bytes"
    # ```
    def number_to_human_size(bytes : Number) : String
      units = ["Bytes", "KB", "MB", "GB", "TB", "PB"]
      return "0 Bytes" if bytes == 0

      size = bytes.to_f.abs
      exponent = 0

      while size >= 1024 && exponent < units.size - 1
        size /= 1024.0
        exponent += 1
      end

      if exponent == 0
        "#{bytes.to_i} Bytes"
      else
        prefix = bytes < 0 ? "-" : ""
        "#{prefix}#{sprintf("%.2f", size)} #{units[exponent]}"
      end
    end

    # The first code point of each block of ten Unicode decimal digits
    # (category Nd), as PCRE2 10.49 (Unicode 16.0) matched them with `\d`.
    private DECIMAL_DIGIT_BLOCK_STARTS = [
      0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6,
      0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0,
      0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620,
      0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10, 0x104A0, 0x10D30, 0x10D40,
      0x11066, 0x110F0, 0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0, 0x11650, 0x116C0, 0x116D0,
      0x116DA, 0x11730, 0x118E0, 0x11950, 0x11BF0, 0x11C50, 0x11D50, 0x11DA0, 0x11DE0, 0x11F50,
      0x16130, 0x16A60, 0x16AC0, 0x16B50, 0x16D70, 0x1CCF0, 0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC,
      0x1D7F6, 0x1E140, 0x1E2F0, 0x1E4F0, 0x1E5F1, 0x1E950, 0x1FBF0,
    ]

    # Returns *text* with *delimiter* between every three digits of each run
    # of decimal digits, counted from the run's right end (`"1234567"`
    # becomes `"1,234,567"`). Other characters stay where they are.
    #
    # It finds the cuts on the reversed text, as the lookahead pattern it
    # replaced did: `String#reverse` keeps grapheme clusters whole, so a digit
    # that carries a combining mark ends a run exactly where it did before.
    # Every cut falls between two digits, so reversing each piece back gives
    # the original text, and the delimiter joins the pieces as written.
    private def group_digits(text : String, delimiter : String) : String
      reversed_chars = text.reverse.chars
      list_of_reversed_pieces = [] of String
      piece = String::Builder.new
      index = 0
      while index < reversed_chars.size
        if digit_group_continues?(reversed_chars, index)
          3.times { |offset| piece << reversed_chars[index + offset] }
          list_of_reversed_pieces << piece.to_s
          piece = String::Builder.new
          index += 3
        else
          piece << reversed_chars[index]
          index += 1
        end
      end
      list_of_reversed_pieces << piece.to_s
      list_of_reversed_pieces.reverse.map(&.reverse).join(delimiter)
    end

    # True when three decimal digits start at *index* and a fourth follows.
    private def digit_group_continues?(chars : Array(Char), index : Int32) : Bool
      return false if index + 3 >= chars.size
      (index..index + 3).all? { |position| decimal_digit?(chars[position]) }
    end

    # Returns `true` when *char* is a Unicode decimal digit, as `\d` judged it.
    private def decimal_digit?(char : Char) : Bool
      return char.ascii_number? if char.ascii?

      code_point = char.ord
      following_block = DECIMAL_DIGIT_BLOCK_STARTS.bsearch_index { |block_start| block_start > code_point } || DECIMAL_DIGIT_BLOCK_STARTS.size
      return false if following_block == 0
      code_point <= DECIMAL_DIGIT_BLOCK_STARTS[following_block - 1] + 9
    end
  end
end
