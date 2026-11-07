module Amber::Support
  # Checks for the text formats Amber validates, each one a single left-to-right
  # pass over the bytes. Their cost grows with the length of the text whatever the
  # text contains, and they use no regex engine.
  module TextFormats
    # `name@example.com`: the strict shape. The last domain label is two or more letters.
    def self.email?(text : String) : Bool
      local_part, separator, domain = text.partition('@')
      return false if separator.empty? || local_part.empty?
      return false unless local_part.each_byte.all? { |byte| alphanumeric?(byte) || byte.unsafe_chr.in?('.', '_', '%', '+', '-') }

      last_dot_index = domain.to_slice.rindex('.'.ord.to_u8)
      return false unless last_dot_index

      top_level_label = domain.byte_slice(last_dot_index + 1)
      return false unless top_level_label.bytesize >= 2 && top_level_label.each_byte.all? { |byte| letter?(byte) }

      domain.byte_slice(0, last_dot_index).split('.').all? { |label| email_domain_label?(label) }
    end

    # `anything@anything.anything`: one `@`, no whitespace, and a dot with text on
    # both sides somewhere after the `@`.
    def self.loose_email?(text : String) : Bool
      local_part, separator, domain = text.partition('@')
      return false if separator.empty? || local_part.empty? || domain.empty?
      return false if domain.includes?('@') || text.each_char.any? { |char| whitespace?(char) }

      dot_index = domain.byte_index('.', 1)
      !!dot_index && dot_index + 1 < domain.bytesize
    end

    # The relaxed web address shape: an optional `http://` or `https://`, then letters,
    # digits, `.` and `-`, a dot, and two lowercase letters or dots. The rest may hold
    # word characters, spaces, `/`, `.` and `-`.
    def self.web_address?(text : String) : Bool
      rest = without_web_scheme(text)
      return false unless rest.each_char.all? { |char| web_address_char?(char) }

      rest.to_slice.each_with_index do |byte, byte_index|
        break unless lowercase_letter_or_digit?(byte) || byte === '.' || byte === '-'
        next unless byte === '.' && byte_index >= 1 && byte_index + 2 < rest.bytesize

        return true if lowercase_letter_or_dot?(rest.to_slice[byte_index + 1]) && lowercase_letter_or_dot?(rest.to_slice[byte_index + 2])
      end

      false
    end

    # True when *text* begins with a location: an optional `http://` or `https://`,
    # then host characters containing a dot followed by two or more letters or digits.
    # Only the beginning is judged; `String#url?` accepts whatever follows it.
    def self.location_prefix?(text : String) : Bool
      rest = without_web_scheme(text)

      rest.to_slice.each_with_index do |byte, byte_index|
        break unless alphanumeric?(byte) || byte === '.' || byte === '-' || byte === '_'
        next unless byte === '.' && byte_index >= 1 && byte_index + 2 < rest.bytesize

        return true if alphanumeric?(rest.to_slice[byte_index + 1]) && alphanumeric?(rest.to_slice[byte_index + 2])
      end

      false
    end

    # `123e4567-e89b-12d3-a456-426614174000`, in either case.
    def self.uuid?(text : String) : Bool
      return false unless text.bytesize == 36

      text.to_slice.each_with_index do |byte, byte_index|
        return false unless byte_index.in?(8, 13, 18, 23) ? byte === '-' : hex_digit?(byte)
      end

      true
    end

    # Four dot-separated numbers from 0 to 255, each one to three digits. Leading
    # zeros are accepted.
    def self.ipv4?(text : String) : Bool
      list_of_octets = text.split('.')
      list_of_octets.size == 4 && list_of_octets.all? { |octet| ipv4_octet?(octet) }
    end

    # Eight groups of one to four hex digits, or up to seven with one `::`, plus three
    # special shapes: `fe80:` with a `%zone`, `::` or `::ffff:` or `::ffff:0:` before
    # an IPv4 address, and one to four groups and `::` before an IPv4 address.
    def self.ipv6?(text : String) : Bool
      link_local_with_zone?(text) || mapped_ipv4?(text) || ipv6_groups?(text)
    end

    # Labels of 1 to 63 letters, digits and hyphens, joined by dots, where each label
    # begins and ends with a letter or digit.
    def self.hostname?(text : String) : Bool
      text.split('.').all? { |label| hostname_label?(label) }
    end

    # E.164: an optional `+`, a digit from 1 to 9, then 5 to 14 more digits.
    def self.phone?(text : String) : Bool
      digits = text.starts_with?('+') ? text.byte_slice(1) : text
      return false unless digits.bytesize.in?(6..15) && digits.each_byte.all? { |byte| digit?(byte) }

      !digits.starts_with?('0')
    end

    # `H:MM:SS` or `HH:MM:SS` on a 24-hour clock.
    def self.time_of_day?(text : String) : Bool
      hour, minute_separator, rest = text.partition(':')
      minute, second_separator, second = rest.partition(':')
      return false if minute_separator.empty? || second_separator.empty?

      hour_of_day?(hour) && minute_or_second?(minute) && minute_or_second?(second)
    end

    private def self.without_web_scheme(text : String) : String
      if text.starts_with?("https://")
        text.byte_slice(8)
      elsif text.starts_with?("http://")
        text.byte_slice(7)
      else
        text
      end
    end

    private def self.email_domain_label?(label : String) : Bool
      return false if label.empty? || label.starts_with?('-') || label.ends_with?('-')

      label.each_byte.all? { |byte| alphanumeric?(byte) || byte === '-' }
    end

    private def self.hostname_label?(label : String) : Bool
      label.bytesize <= 63 && email_domain_label?(label)
    end

    private def self.ipv4_octet?(octet : String) : Bool
      return false unless octet.bytesize.in?(1..3) && octet.each_byte.all? { |byte| digit?(byte) }

      octet.to_i <= 255
    end

    # The stricter octet of the IPv4 tail in an IPv6 address: `05` passes and `005`
    # does not.
    private def self.ipv6_tail_octet?(octet : String) : Bool
      return false unless ipv4_octet?(octet)

      octet.bytesize < 3 || !octet.starts_with?('0')
    end

    private def self.ipv6_tail?(text : String) : Bool
      list_of_octets = text.split('.')
      list_of_octets.size == 4 && list_of_octets.all? { |octet| ipv6_tail_octet?(octet) }
    end

    private def self.ipv6_group?(group : String) : Bool
      group.bytesize.in?(1..4) && group.each_byte.all? { |byte| hex_digit?(byte) }
    end

    private def self.ipv6_groups?(text : String) : Bool
      compression_index = text.byte_index("::")

      unless compression_index
        list_of_groups = text.split(':')
        return list_of_groups.size == 8 && list_of_groups.all? { |group| ipv6_group?(group) }
      end

      before = text.byte_slice(0, compression_index)
      after = text.byte_slice(compression_index + 2)
      list_of_groups_before = before.empty? ? [] of String : before.split(':')
      list_of_groups_after = after.empty? ? [] of String : after.split(':')

      list_of_groups_before.size + list_of_groups_after.size <= 7 &&
        list_of_groups_before.all? { |group| ipv6_group?(group) } &&
        list_of_groups_after.all? { |group| ipv6_group?(group) }
    end

    private def self.link_local_with_zone?(text : String) : Bool
      return false unless text.starts_with?("fe80:")

      address, separator, zone = text.partition('%')
      return false if separator.empty? || zone.empty? || !zone.each_byte.all? { |byte| alphanumeric?(byte) }

      list_of_parts = address.byte_slice(5).split(':')
      return address.bytesize == 5 if list_of_parts == [""]
      return false unless list_of_parts.first.empty? && list_of_parts.size <= 5

      list_of_parts.skip(1).all? { |part| part.empty? || ipv6_group?(part) }
    end

    private def self.mapped_ipv4?(text : String) : Bool
      return false unless text.includes?('.')

      if text.starts_with?("::")
        rest = text.byte_slice(2)
        return true if ipv6_tail?(rest)

        if rest.starts_with?("ffff:")
          after_marker = rest.byte_slice(5)
          return true if ipv6_tail?(after_marker)

          zeros, separator, tail = after_marker.partition(':')
          return separator == ":" && zeros.bytesize.in?(1..4) && zeros.each_byte.all? { |byte| byte === '0' } && ipv6_tail?(tail)
        end

        return false
      end

      compression_index = text.byte_index("::")
      return false unless compression_index

      list_of_groups = text.byte_slice(0, compression_index).split(':')
      list_of_groups.size <= 4 && list_of_groups.all? { |group| ipv6_group?(group) } && ipv6_tail?(text.byte_slice(compression_index + 2))
    end

    private def self.hour_of_day?(hour : String) : Bool
      return false unless hour.bytesize.in?(1..2) && hour.each_byte.all? { |byte| digit?(byte) }

      hour.to_i <= 23
    end

    private def self.minute_or_second?(text : String) : Bool
      text.bytesize == 2 && text.each_byte.all? { |byte| digit?(byte) } && text.to_i <= 59
    end

    private def self.digit?(byte : UInt8) : Bool
      byte.unsafe_chr.ascii_number?
    end

    private def self.letter?(byte : UInt8) : Bool
      byte.unsafe_chr.ascii_letter?
    end

    private def self.alphanumeric?(byte : UInt8) : Bool
      byte.unsafe_chr.ascii_alphanumeric?
    end

    private def self.hex_digit?(byte : UInt8) : Bool
      byte.unsafe_chr.hex?
    end

    private def self.lowercase_letter_or_digit?(byte : UInt8) : Bool
      byte.unsafe_chr.ascii_lowercase? || digit?(byte)
    end

    private def self.lowercase_letter_or_dot?(byte : UInt8) : Bool
      byte.unsafe_chr.ascii_lowercase? || byte === '.'
    end

    # Unicode spaces, plus the two control characters Unicode counts as breaks and
    # the Mongolian vowel separator, as `\s` treats them.
    private def self.whitespace?(char : Char) : Bool
      char.whitespace? || char.in?('\u0085', '᠎')
    end

    # Unicode category Pc, which `\w` counts as a word character.
    private def self.connector_punctuation?(char : Char) : Bool
      char.in?('_', '‿', '⁀', '⁔', '︳', '︴', '﹍', '﹎', '﹏', '＿')
    end

    private def self.web_address_char?(char : Char) : Bool
      char.letter? || char.number? || char.mark? || char.in?(' ', '/', '.', '-') || connector_punctuation?(char)
    end
  end
end
