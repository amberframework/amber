require "./certificate"

module Amber::Beryl::Certificates
  # The name a client expects the server to prove: a DNS name or an IP
  # address (RFC 9525's DNS-ID and IP-ID).
  #
  # ```
  # identity = Amber::Beryl::Certificates::ServiceIdentity.new("www.example.com")
  # identity.matches?(certificate) # => true when a SAN dNSName matches
  # ```
  #
  # Matching follows RFC 9525 §6:
  # - a DNS name is compared with the certificate's subject alternative
  #   dNSName entries only; the common name is never used (§6.2.1);
  # - comparison is case-insensitive over ASCII (§6.3), on A-labels: a
  #   name with characters outside ASCII is refused, and the caller converts
  #   an internationalized name to its A-label form first;
  # - a presented name may start with one wildcard label `*`, which matches
  #   exactly one non-empty label of the reference name (§6.3); a wildcard
  #   anywhere else, a partial wildcard such as `f*.example.com`, and a
  #   wildcard covering a whole public suffix (`*.com`, `*.co.uk`) do not
  #   match;
  # - an IP address is compared with the subject alternative iPAddress
  #   entries only, byte for byte (§6.2.2).
  struct ServiceIdentity
    # The DNS name in lowercase, without a final dot, or `nil` for an IP.
    getter domain_name : String?
    # The 4 or 16 address bytes, or `nil` for a DNS name.
    getter ip_address : Bytes?

    # Reads *reference* as an IP address when it is one in textual form
    # (dotted-quad IPv4 or RFC 4291 IPv6), and as a DNS name otherwise.
    # Raises `ArgumentError` when it is neither.
    def initialize(reference : String)
      if address = ServiceIdentity.parse_ip_address(reference)
        @ip_address = address
        @domain_name = nil
      else
        name = reference.ends_with?('.') ? reference[0, reference.size - 1] : reference
        unless ServiceIdentity.valid_reference_name?(name)
          raise ArgumentError.new("#{reference.inspect} is neither an IP address nor a DNS name in A-label form")
        end
        @domain_name = name.downcase
        @ip_address = nil
      end
    end

    # Returns whether a subject alternative name of *certificate* matches.
    def matches?(certificate : Certificate) : Bool
      if address = @ip_address
        certificate.list_of_ip_addresses.any? { |presented| presented == address }
      elsif name = @domain_name
        certificate.list_of_dns_names.any? { |presented| ServiceIdentity.domain_name_matches?(presented, name) }
      else
        false
      end
    end

    def to_s(io : IO) : Nil
      if address = @ip_address
        io << ServiceIdentity.format_ip_address(address)
      else
        io << @domain_name
      end
    end

    # :nodoc:
    #
    # Returns whether the presented DNS identifier *presented* (from a SAN)
    # matches the reference name *reference* (lowercase, validated).
    def self.domain_name_matches?(presented : String, reference : String) : Bool
      presented = presented.downcase
      presented = presented[0, presented.size - 1] if presented.ends_with?('.')
      if presented.starts_with?("*.")
        base = presented[2..]
        return false unless valid_host_name?(base) && wildcard_base_allowed?(base)

        first_dot = reference.index('.')
        return false unless first_dot && first_dot > 0
        reference[first_dot + 1..] == base
      else
        valid_host_name?(presented) && presented == reference
      end
    end

    # :nodoc:
    #
    # A wildcard needs at least two labels after it and must not cover a
    # public suffix (CA/Browser Forum baseline requirements §3.2.2.6).
    def self.wildcard_base_allowed?(base : String) : Bool
      base.includes?('.') && !PublicSuffixList.public_suffix?(base)
    end

    # :nodoc:
    #
    # A host name of letter-digit-hyphen labels (RFC 1123 §2.1, RFC 5890
    # A-labels), each 1 to 63 characters, not starting or ending with a
    # hyphen, 253 characters at most.
    def self.valid_host_name?(name : String) : Bool
      return false if name.empty? || name.bytesize > 253

      name.split('.').all? do |label|
        !label.empty? && label.bytesize <= 63 && !label.starts_with?('-') && !label.ends_with?('-') &&
          label.each_byte.all? { |byte| byte.unsafe_chr.ascii_alphanumeric? || byte == '-'.ord }
      end
    end

    # :nodoc:
    #
    # A reference name may also hold underscores, which appear in service
    # names; they never match a presented name, which may not hold them.
    def self.valid_reference_name?(name : String) : Bool
      valid_host_name?(name.gsub('_', 'a')) && !all_numeric_labels?(name)
    end

    private def self.all_numeric_labels?(name : String) : Bool
      name.split('.').all? { |label| !label.empty? && label.each_char.all?(&.ascii_number?) }
    end

    # :nodoc:
    #
    # Reads a textual IPv4 (four decimal octets, no leading zeros) or IPv6
    # address and returns its bytes, or `nil`.
    def self.parse_ip_address(text : String) : Bytes?
      if text.includes?(':')
        parse_ipv6(text)
      else
        parse_ipv4(text)
      end
    end

    private def self.parse_ipv4(text : String) : Bytes?
      list_of_parts = text.split('.')
      return nil unless list_of_parts.size == 4

      bytes = Bytes.new(4)
      list_of_parts.each_with_index do |part, index|
        return nil if part.empty? || part.size > 3 || !part.each_char.all?(&.ascii_number?)
        return nil if part.size > 1 && part.starts_with?('0')
        value = part.to_i
        return nil if value > 255
        bytes[index] = value.to_u8
      end
      bytes
    end

    private def self.parse_ipv6(text : String) : Bytes?
      return nil if text.size > 45

      halves = text.split("::", remove_empty: false)
      return nil if halves.size > 2

      head = halves[0].empty? ? [] of String : halves[0].split(':')
      tail = halves.size == 2 && !halves[1].empty? ? halves[1].split(':') : [] of String
      groups = [] of UInt16
      embedded_ipv4 = nil
      if (last = (halves.size == 2 ? tail : head).last?) && last.includes?('.')
        embedded_ipv4 = parse_ipv4(last)
        return nil unless embedded_ipv4
        if halves.size == 2
          tail = tail[0, tail.size - 1]
        else
          head = head[0, head.size - 1]
        end
      end
      parsed_head = parse_hex_groups(head)
      parsed_tail = parse_hex_groups(tail)
      return nil unless parsed_head && parsed_tail

      group_count = parsed_head.size + parsed_tail.size + (embedded_ipv4 ? 2 : 0)
      if halves.size == 2
        return nil if group_count > 7
        groups.concat(parsed_head)
        (8 - group_count).times { groups << 0_u16 }
        groups.concat(parsed_tail)
      else
        return nil unless group_count == 8
        groups.concat(parsed_head)
      end
      bytes = Bytes.new(16)
      groups.each_with_index do |group, index|
        bytes[2 * index] = (group >> 8).to_u8
        bytes[2 * index + 1] = (group & 0xff).to_u8
      end
      if ipv4 = embedded_ipv4
        ipv4.copy_to(bytes[12, 4])
      end
      bytes
    end

    private def self.parse_hex_groups(list_of_groups : Array(String)) : Array(UInt16)?
      list_of_groups.map do |group|
        return nil if group.empty? || group.size > 4 || !group.each_char.all?(&.hex?)
        group.to_u16(16)
      end
    end

    # :nodoc:
    #
    # The canonical text of an address: dotted decimal for IPv4, RFC 5952
    # §4 for IPv6 (lowercase, no leading zeros, the longest run of two or
    # more zero groups shortened to "::", the first such run on a tie).
    def self.format_ip_address(bytes : Bytes) : String
      return bytes.join('.') if bytes.size == 4
      return bytes.hexstring unless bytes.size == 16

      groups = Array(UInt16).new(8) { |index| (bytes[2 * index].to_u16 << 8) | bytes[2 * index + 1] }
      best_start, best_length = -1, 0
      index = 0
      while index < 8
        if groups[index] == 0
          run_start = index
          while index < 8 && groups[index] == 0
            index += 1
          end
          if index - run_start > best_length
            best_start, best_length = run_start, index - run_start
          end
        else
          index += 1
        end
      end
      return groups.map(&.to_s(16)).join(':') if best_length < 2

      head = groups[0, best_start].map(&.to_s(16)).join(':')
      tail = groups[best_start + best_length..].map(&.to_s(16)).join(':')
      "#{head}::#{tail}"
    end
  end
end
