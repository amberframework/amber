require "./object_identifiers"
require "./error"

module Amber::Beryl::Certificates
  # An X.501 distinguished name (RFC 5280 §4.1.2.4): a sequence of
  # relative distinguished names, each a set of attribute type and value
  # pairs.
  #
  # Names are compared byte for byte on their encoding, as Go, rustls-webpki
  # and BoringSSL compare issuer and subject when building paths; the RFC
  # 4518 string preparation that RFC 5280 §7.1 describes is not applied.
  struct DistinguishedName
    # One attribute: its type and its value element (tag and contents).
    record Attribute, type : Encoding::DER::ObjectIdentifier, value : Encoding::DER::Element do
      # The value's bytes when it is one of the string types a name may
      # use, or `nil` for any other value.
      def string_value : Bytes?
        tag = value.tag
        return nil unless tag.tag_class.universal? && !tag.is_constructed

        case tag.number
        when 12, 19, 20, 22, 28, 30 then value.content
        else                             nil
        end
      end
    end

    # The whole encoding, the SEQUENCE included.
    getter encoded : Bytes
    getter list_of_relative_names : Array(Array(Attribute))

    def initialize(@encoded : Bytes, @list_of_relative_names : Array(Array(Attribute)))
    end

    # Reads a Name from *reader*.
    def self.read(reader : Encoding::DER::Reader) : DistinguishedName
      element = reader.read_element(Encoding::DER::SEQUENCE)
      list_of_relative_names = reader.enter(element) do |sequence|
        relative_names = [] of Array(Attribute)
        until sequence.at_end?
          relative_name = sequence.read_constructed(Encoding::DER::SET) do |set|
            attributes = [] of Attribute
            until set.at_end?
              attribute = set.read_sequence do |pair|
                type = pair.read_object_identifier
                value = pair.read_element
                if reason = DistinguishedName.malformed_value_reason(value)
                  raise Encoding::MalformedEncoding.new(reason, value.offset)
                end
                Attribute.new(type, value)
              end
              attributes << attribute
            end
            raise Encoding::MalformedEncoding.new("a relative distinguished name is empty", element.offset) if attributes.empty?
            attributes
          end
          relative_names << relative_name
        end
        relative_names
      end
      DistinguishedName.new(element.encoded, list_of_relative_names)
    end

    # Why *value* cannot be an attribute value, or `nil` when it can. A
    # value is a UTF8String, PrintableString, TeletexString, IA5String,
    # NumericString, UniversalString or BMPString with contents that type
    # allows, a BIT STRING (x500UniqueIdentifier) or a SEQUENCE: the types
    # OpenSSL accepts in names. RFC 5280 declares AttributeValue as
    # ANY, but every other type is refused so that a name means the same
    # here as in other verifiers.
    def self.malformed_value_reason(value : Encoding::DER::Element) : String?
      tag = value.tag
      return "a name attribute value has a #{tag} tag" unless tag.tag_class.universal?
      if tag.is_constructed
        return tag.number == 16 ? nil : "a name attribute value has a #{tag} tag"
      end

      content = value.content
      case tag.number
      when 3
        Encoding::DER.decode_bit_string(value)
        nil
      when 12
        String.new(content).valid_encoding? ? nil : "a UTF8String that is not UTF-8"
      when 18
        content.all? { |byte| byte.unsafe_chr.ascii_number? || byte == 0x20 } ? nil : "a NumericString with a character outside digits and space"
      when 19
        content.all? { |byte| printable_string_byte?(byte) } ? nil : "a PrintableString with a character outside its alphabet"
      when 22
        content.all? { |byte| byte < 0x80 } ? nil : "an IA5String with a byte outside ASCII"
      when 28
        return "a UniversalString whose length is not a multiple of 4" unless content.size % 4 == 0
        valid = (0...content.size // 4).all? do |index|
          scalar_value?(IO::ByteFormat::BigEndian.decode(UInt32, content[index * 4, 4]))
        end
        valid ? nil : "a UniversalString with a value that is not a Unicode character"
      when 30
        return "a BMPString whose length is odd" unless content.size.even?
        valid = (0...content.size // 2).all? do |index|
          scalar_value?(IO::ByteFormat::BigEndian.decode(UInt16, content[index * 2, 2]).to_u32)
        end
        valid ? nil : "a BMPString with a surrogate code unit"
      when 20
        nil
      else
        "a name attribute value has a #{tag} tag"
      end
    end

    # Whether *value* is a Unicode scalar value: at most 0x10FFFF and
    # outside the surrogates.
    private def self.scalar_value?(value : UInt32) : Bool
      value <= 0x10FFFF && !(0xD800 <= value <= 0xDFFF)
    end

    # The PrintableString alphabet (X.680 §41.4), with `*` and `&`, which
    # issued certificates use and Go accepts.
    private def self.printable_string_byte?(byte : UInt8) : Bool
      character = byte.unsafe_chr
      character.ascii_alphanumeric? || " '()+,-./:=?*&".includes?(character)
    end

    def empty? : Bool
      @list_of_relative_names.empty?
    end

    def ==(other : DistinguishedName) : Bool
      @encoded == other.encoded
    end

    def hash(hasher)
      @encoded.hash(hasher)
    end

    # Every attribute of type *type*, in order.
    def list_of_values(type : Encoding::DER::ObjectIdentifier) : Array(Attribute)
      @list_of_relative_names.flat_map { |relative_name| relative_name.select { |attribute| attribute.type == type } }
    end

    # The common name values (2.5.4.3) as bytes.
    def list_of_common_names : Array(Bytes)
      list_of_values(ObjectIdentifiers::COMMON_NAME).compact_map(&.string_value)
    end

    # Returns whether this name begins with every relative distinguished
    # name of *prefix*, in order: the test a directoryName name constraint
    # applies (RFC 5280 §4.2.1.10). Each relative name is compared on its
    # encoding.
    def starts_with?(prefix : DistinguishedName) : Bool
      return false if prefix.list_of_relative_names.size > @list_of_relative_names.size

      prefix.list_of_relative_names.each_with_index.all? do |relative_name, index|
        DistinguishedName.encode_relative_name(relative_name) == DistinguishedName.encode_relative_name(@list_of_relative_names[index])
      end
    end

    # :nodoc:
    def self.encode_relative_name(relative_name : Array(Attribute)) : Bytes
      io = IO::Memory.new
      relative_name.each do |attribute|
        io.write(attribute.type.encoded)
        io.write(attribute.value.encoded)
      end
      io.to_slice
    end

    # A readable form such as "CN=example.com, O=Example", for messages.
    def to_s(io : IO) : Nil
      is_first = true
      @list_of_relative_names.each do |relative_name|
        relative_name.each do |attribute|
          io << ", " unless is_first
          is_first = false
          io << (attribute.type == ObjectIdentifiers::COMMON_NAME ? "CN" : attribute.type.to_s) << '='
          if string = attribute.string_value
            io << String.new(string).scrub
          else
            io << "#" << attribute.value.content.hexstring
          end
        end
      end
    end
  end
end
