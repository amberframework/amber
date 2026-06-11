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

      formatted = digits.reverse.gsub(/(\d{3})(?=\d)/) do |match|
        match + delimiter
      end.reverse

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

      delimited = digits.reverse.gsub(/(\d{3})(?=\d)/) do |match|
        match + ","
      end.reverse

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
  end
end
