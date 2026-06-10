# Data sanitization parser
module Amber::Schema::Parser
  class Sanitizer < Base
    # Sanitization options
    enum Option
      TrimWhitespace
      RemoveHTML
      EscapeHTML
      Lowercase
      Uppercase
      RemoveNonPrintable
      NormalizeWhitespace
    end

    def initialize(@options : Array(Option) = [] of Option)
    end

    def parse(value : JSON::Any) : JSON::Any
      case value.raw
      when String
        sanitized = value.as_s
        @options.each do |option|
          sanitized = apply_option(sanitized, option)
        end
        JSON::Any.new(sanitized)
      when Hash
        # Recursively sanitize hash values
        if hash = value.as_h?
          sanitized_hash = {} of String => JSON::Any
          hash.each do |key, val|
            sanitized_hash[key] = parse(val)
          end
          JSON::Any.new(sanitized_hash)
        else
          value
        end
      when Array
        # Recursively sanitize array elements
        if array = value.as_a?
          sanitized_array = array.map { |element| parse(element) }
          JSON::Any.new(sanitized_array)
        else
          value
        end
      else
        value
      end
    end

    def can_parse?(value : JSON::Any) : Bool
      true
    end

    private def apply_option(text : String, option : Option) : String
      case option
      when Option::TrimWhitespace
        text.strip
      when Option::RemoveHTML
        remove_html_tags(text)
      when Option::EscapeHTML
        HTML.escape(text)
      when Option::Lowercase
        text.downcase
      when Option::Uppercase
        text.upcase
      when Option::RemoveNonPrintable
        text.gsub(/[^\x20-\x7E]/, "")
      when Option::NormalizeWhitespace
        text.gsub(/\s+/, " ").strip
      else
        text
      end
    end

    private def remove_html_tags(text : String) : String
      # Simple HTML tag removal (not perfect but good for basic cases)
      text.gsub(/<[^>]*>/, "")
    end

    # Factory methods for common sanitizers
    def self.for_text : Sanitizer
      new([
        Option::TrimWhitespace,
        Option::NormalizeWhitespace,
        Option::RemoveHTML,
      ])
    end

    def self.for_html : Sanitizer
      new([
        Option::TrimWhitespace,
        Option::EscapeHTML,
      ])
    end

    def self.for_username : Sanitizer
      new([
        Option::TrimWhitespace,
        Option::Lowercase,
        Option::RemoveNonPrintable,
      ])
    end

    def self.for_email : Sanitizer
      new([
        Option::TrimWhitespace,
        Option::Lowercase,
      ])
    end
  end
end
