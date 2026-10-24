require "socket"

module Amber::Support
  # One entry of the `server.trusted_proxies` setting: a single IP address or
  # a CIDR block, such as `"127.0.0.1"`, `"10.0.0.0/8"`, or `"fd00::/8"`.
  #
  # Addresses are compared as 128-bit values. IPv4 addresses and blocks are
  # mapped into `::ffff:0:0/96`, so a peer that reaches a dual-stack listener
  # as `::ffff:127.0.0.1` still matches the block `127.0.0.0/8`.
  #
  # ```
  # network = Amber::Support::TrustedProxyNetwork.parse("10.0.0.0/8")
  # network.includes?(Socket::IPAddress.new("10.1.2.3", 0))    # => true
  # network.includes?(Socket::IPAddress.new("192.168.0.1", 0)) # => false
  # ```
  struct TrustedProxyNetwork
    alias AddressBytes = StaticArray(UInt8, 16)

    private IPV4_MAPPED_PREFIX_LENGTH = 96

    # The entry as it was written in the configuration.
    getter notation : String

    @network : AddressBytes
    @prefix_length : Int32

    private def initialize(@notation : String, @network : AddressBytes, @prefix_length : Int32)
    end

    # Parses *notation* into a network, raising
    # `Amber::Exceptions::ConfigurationError` when it is not an IP address or
    # CIDR block.
    def self.parse(notation : String) : self
      if network = parse?(notation)
        return network
      end

      raise Amber::Exceptions::ConfigurationError.new(
        "server.trusted_proxies entry #{notation.inspect} is not an IP address or CIDR block"
      )
    end

    # Parses *notation* into a network, returning `nil` when it is not an IP
    # address or CIDR block.
    def self.parse?(notation : String) : self?
      address_text, separator, length_text = notation.strip.partition('/')
      parsed_address = address_bytes?(address_text)
      return unless parsed_address

      bytes, is_ipv4 = parsed_address
      maximum_length = is_ipv4 ? 32 : 128
      prefix_length = maximum_length
      unless separator.empty?
        written_length = length_text.to_i?
        return unless written_length
        return unless written_length.in?(0..maximum_length)
        prefix_length = written_length
      end
      prefix_length += IPV4_MAPPED_PREFIX_LENGTH if is_ipv4

      new(notation, masked(bytes, prefix_length), prefix_length)
    end

    # Returns `true` when *address* falls inside this network. Peers that are
    # not IP sockets (for example UNIX sockets) never match.
    def includes?(address : Socket::Address) : Bool
      return false unless address.is_a?(Socket::IPAddress)

      parsed_address = self.class.address_bytes?(address.address)
      return false unless parsed_address

      bytes, _is_ipv4 = parsed_address
      self.class.masked(bytes, @prefix_length) == @network
    end

    # :nodoc:
    #
    # Converts an IPv4 or IPv6 text address into 16 bytes, mapping IPv4 into
    # `::ffff:0:0/96`. The second value reports whether the text was IPv4.
    # An IPv6 zone suffix (`fe80::1%en0`) is ignored.
    def self.address_bytes?(text : String) : Tuple(AddressBytes, Bool)?
      bytes = AddressBytes.new(0_u8)

      if ipv4_fields = Socket::IPAddress.parse_v4_fields?(text)
        bytes[10] = 0xff_u8
        bytes[11] = 0xff_u8
        4.times { |index| bytes[12 + index] = ipv4_fields[index] }
        return {bytes, true}
      end

      address_without_zone = text.partition('%').first
      if ipv6_fields = Socket::IPAddress.parse_v6_fields?(address_without_zone)
        8.times do |index|
          bytes[index * 2] = (ipv6_fields[index] >> 8).to_u8
          bytes[index * 2 + 1] = (ipv6_fields[index] & 0xff).to_u8
        end
        return {bytes, false}
      end

      nil
    end

    # :nodoc:
    #
    # Returns *bytes* with every bit after the first *prefix_length* bits cleared.
    def self.masked(bytes : AddressBytes, prefix_length : Int32) : AddressBytes
      result = bytes
      16.times do |index|
        bits_kept = (prefix_length - index * 8).clamp(0, 8)
        mask = bits_kept == 0 ? 0_u8 : (0xff_u8 << (8 - bits_kept))
        result[index] = bytes[index] & mask
      end
      result
    end
  end
end
