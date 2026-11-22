require "./mappings/*"

module Amber::Markdown::HTMLEntities
  module ExtendToHTML
    def decode_entities(source : String)
      Decoder.decode(source)
    end

    def decode_entity(source : String)
      Decoder.decode_entity(source)
    end
  end

  module Decoder
    REGEX = /&(?:([a-zA-Z0-9]{2,32};)|(#[xX][\da-fA-F]+;?|#\d+;?))/

    def self.decode(source)
      source.gsub(REGEX) do |chars|
        decode_entity(chars[1..-2])
      end
    end

    def self.decode_entity(chars)
      if chars[0] == '#'
        if chars.size > 1
          if chars[1].downcase == 'x'
            if chars.size > 2
              return decode_codepoint(chars[2..-1].to_i(16))
            end
          else
            return decode_codepoint(chars[1..-1].to_i(10))
          end
        end
      else
        entities_key = chars[0..-1]
        if resolved_entity = Amber::Markdown::HTMLEntities::ENTITIES_MAPPINGS[entities_key]?
          return resolved_entity
        end
      end

      "&#{chars};"
    end

    def self.decode_codepoint(codepoint)
      return "\uFFFD" if codepoint >= 0xD800 && codepoint <= 0xDFFF || codepoint > 0x10FFF

      if decoded = Amber::Markdown::HTMLEntities::DECODE_MAPPINGS[codepoint]?
        codepoint = decoded
      end

      codepoint.unsafe_chr
    end
  end
end

module HTML
  extend Amber::Markdown::HTMLEntities::ExtendToHTML
end
