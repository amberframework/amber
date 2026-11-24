require "./error"

module Amber::Beryl::Encoding
  # Reads DER, the Distinguished Encoding Rules of ITU-T X.690 §10, the
  # encoding of certificates, keys and signatures.
  #
  # Only the one canonical encoding of each value is accepted: definite
  # lengths in their shortest form, tags in their shortest form, minimal
  # integers, BOOLEAN as `0x00` or `0xFF`, BIT STRING padding bits set to
  # zero, and the two time forms RFC 5280 §4.1.2.5 allows. Every read checks
  # the bytes left before it touches them, and nesting deeper than
  # `Limits#largest_nesting_depth` is refused, so a hostile input can raise
  # `MalformedEncoding` or `LimitExceeded` and nothing else.
  #
  # ```
  # reader = Amber::Beryl::Encoding::DER::Reader.new(certificate_bytes)
  # reader.read_sequence do |certificate|
  #   to_be_signed = certificate.read_element(DER::SEQUENCE)
  #   # ...
  # end
  # reader.finish
  # ```
  module DistinguishedEncodingRules
    # The bounds a reader holds every input to. Defaults follow the plan's
    # limits for untrusted ASN.1: nesting no deeper than 32 and one input
    # no larger than 64 KiB.
    struct Limits
      getter largest_nesting_depth : Int32
      getter largest_input_bytesize : Int32

      def initialize(*, @largest_nesting_depth : Int32 = 32, @largest_input_bytesize : Int32 = 65_536)
      end
    end

    # The four tag classes of X.690 §8.1.2.2.
    enum TagClass : UInt8
      Universal       = 0
      Application     = 1
      ContextSpecific = 2
      Private         = 3
    end

    # A tag: its class, whether the element is constructed, and its number.
    record Tag, tag_class : TagClass, is_constructed : Bool, number : UInt32 do
      def self.universal(number : UInt32, *, is_constructed : Bool = false) : Tag
        Tag.new(TagClass::Universal, is_constructed, number)
      end

      # `[number]` with context-specific class, as the X.509 modules write
      # their optional fields.
      def self.context_specific(number : UInt32, *, is_constructed : Bool) : Tag
        Tag.new(TagClass::ContextSpecific, is_constructed, number)
      end

      def to_s(io : IO) : Nil
        if tag_class.universal?
          io << "UNIVERSAL " << number
        else
          io << '[' << tag_class << ' ' << number << ']'
        end
        io << " (constructed)" if is_constructed
      end
    end

    BOOLEAN           = Tag.universal(1)
    INTEGER           = Tag.universal(2)
    BIT_STRING        = Tag.universal(3)
    OCTET_STRING      = Tag.universal(4)
    NULL              = Tag.universal(5)
    OBJECT_IDENTIFIER = Tag.universal(6)
    UTF8_STRING       = Tag.universal(12)
    SEQUENCE          = Tag.universal(16, is_constructed: true)
    SET               = Tag.universal(17, is_constructed: true)
    PRINTABLE_STRING  = Tag.universal(19)
    TELETEX_STRING    = Tag.universal(20)
    IA5_STRING        = Tag.universal(22)
    UTC_TIME          = Tag.universal(23)
    GENERALIZED_TIME  = Tag.universal(24)
    UNIVERSAL_STRING  = Tag.universal(28)
    BMP_STRING        = Tag.universal(30)

    # One element read from the input: its tag, its contents, and the whole
    # encoding (tag, length and contents), which signatures and name
    # comparisons need byte for byte.
    struct Element
      getter tag : Tag
      getter content : Bytes
      getter encoded : Bytes
      # The offset of the element from the start of the outermost input.
      getter offset : Int32

      def initialize(@tag : Tag, @content : Bytes, @encoded : Bytes, @offset : Int32)
      end

      # The offset of the first content byte from the start of the
      # outermost input.
      def content_offset : Int32
        @offset + (@encoded.size - @content.size)
      end
    end

    # A bit string: its bytes and the number of unused bits in the last one
    # (0 to 7, always 0 when there are no bytes).
    record BitString, bytes : Bytes, unused_bit_count : Int32 do
      # Returns whether bit *index* is set, counting from the most
      # significant bit of the first byte as X.690 §8.6.2.1 numbers them.
      def bit_set?(index : Int32) : Bool
        byte_index = index // 8
        return false if index < 0 || byte_index >= bytes.size

        (bytes[byte_index] >> (7 - index % 8)) & 1 == 1
      end

      def bit_count : Int32
        bytes.size * 8 - unused_bit_count
      end
    end

    # An object identifier, kept in its encoded form so comparisons and
    # hashing are byte comparisons.
    struct ObjectIdentifier
      getter encoded : Bytes

      def initialize(@encoded : Bytes)
      end

      # Builds an identifier from dotted text such as "1.2.840.113549.1.1.11".
      # For constants written in the source, not for untrusted input.
      def self.parse(dotted : String) : ObjectIdentifier
        list_of_arcs = dotted.split('.').map(&.to_u64)
        raise ArgumentError.new("an object identifier has at least two arcs") if list_of_arcs.size < 2

        encoded = IO::Memory.new
        write_arc(encoded, list_of_arcs[0] * 40 + list_of_arcs[1])
        list_of_arcs.skip(2).each { |arc| write_arc(encoded, arc) }
        ObjectIdentifier.new(encoded.to_slice)
      end

      private def self.write_arc(io : IO, arc : UInt64) : Nil
        list_of_groups = [] of UInt8
        remaining = arc
        loop do
          list_of_groups.unshift((remaining & 0x7f).to_u8)
          remaining >>= 7
          break if remaining == 0
        end
        list_of_groups.each_with_index do |group, index|
          io.write_byte(index == list_of_groups.size - 1 ? group : group | 0x80_u8)
        end
      end

      def ==(other : ObjectIdentifier) : Bool
        @encoded == other.encoded
      end

      def hash(hasher)
        @encoded.hash(hasher)
      end

      # The dotted form, for messages and logs.
      def to_s(io : IO) : Nil
        value = 0_u64
        is_first = true
        @encoded.each do |byte|
          value = (value << 7) | (byte & 0x7f)
          next unless byte & 0x80 == 0

          if is_first
            first_arc = value < 80 ? value // 40 : 2_u64
            io << first_arc << '.' << (value - first_arc * 40)
            is_first = false
          else
            io << '.' << value
          end
          value = 0_u64
        end
      end
    end

    # Reads the elements of one input, or of the contents of one
    # constructed element, front to back.
    class Reader
      getter limits : Limits
      getter depth : Int32
      @bytes : Bytes
      @position : Int32 = 0
      @base_offset : Int32

      # Reads *bytes* (the outermost input). Raises `LimitExceeded` when it
      # is larger than *limits* allow.
      def initialize(bytes : Bytes, @limits : Limits = Limits.new)
        if bytes.size > @limits.largest_input_bytesize
          raise LimitExceeded.new("the input has #{bytes.size} bytes; the limit is #{@limits.largest_input_bytesize}")
        end
        @bytes = bytes
        @depth = 0
        @base_offset = 0
      end

      # :nodoc:
      #
      # A reader over the contents of *element*, one level deeper.
      def initialize(element : Element, @limits : Limits, @depth : Int32)
        if @depth > @limits.largest_nesting_depth
          raise LimitExceeded.new("elements nest deeper than #{@limits.largest_nesting_depth} levels")
        end
        @bytes = element.content
        @base_offset = element.content_offset
      end

      def at_end? : Bool
        @position >= @bytes.size
      end

      def bytes_left : Int32
        @bytes.size - @position
      end

      # Raises unless every byte has been read.
      def finish : Nil
        return if at_end?

        malformed("#{bytes_left} bytes follow the last element")
      end

      # Returns the tag of the next element without reading it, or `nil` at
      # the end.
      def peek_tag : Tag?
        return nil if at_end?

        position = @position
        tag = read_tag
        @position = position
        tag
      end

      # Returns whether the next element has *tag*.
      def next_is?(tag : Tag) : Bool
        peek_tag == tag
      end

      # Reads the next element, whatever its tag.
      def read_element : Element
        start = @position
        malformed("an element was expected, the input ended") if at_end?
        tag = read_tag
        content_bytesize = read_length
        if content_bytesize > bytes_left
          malformed("the length #{content_bytesize} runs past the #{bytes_left} bytes left", start)
        end
        content = @bytes[@position, content_bytesize]
        @position += content_bytesize
        Element.new(tag, content, @bytes[start, @position - start], @base_offset + start)
      end

      # Reads the next element and raises unless its tag is *tag*.
      def read_element(tag : Tag) : Element
        start = @position
        element = read_element
        malformed("expected #{tag}, found #{element.tag}", start) unless element.tag == tag
        element
      end

      # Reads the next element when its tag is *tag*; otherwise reads
      # nothing and returns `nil`.
      def read_optional_element(tag : Tag) : Element?
        next_is?(tag) ? read_element : nil
      end

      # Reads a constructed element with *tag* and yields a reader over its
      # contents, which must be read to the end. Returns the block's value.
      def read_constructed(tag : Tag, & : Reader -> T) : T forall T
        element = read_element(tag)
        malformed("#{tag} must be constructed", element.offset) unless tag.is_constructed
        inner = Reader.new(element, @limits, @depth + 1)
        result = yield inner
        inner.finish
        result
      end

      # Reads a SEQUENCE and yields a reader over its contents.
      def read_sequence(& : Reader -> T) : T forall T
        read_constructed(SEQUENCE) { |inner| yield inner }
      end

      # Yields a reader over the contents of *element* (already read), one
      # level deeper, and requires it to be read to the end.
      def enter(element : Element, & : Reader -> T) : T forall T
        malformed("#{element.tag} must be constructed", element.offset) unless element.tag.is_constructed
        inner = Reader.new(element, @limits, @depth + 1)
        result = yield inner
        inner.finish
        result
      end

      # Checks *element* (already read), and everything inside it, for
      # contents its universal type allows: a BOOLEAN of 0x00 or 0xFF, a
      # minimal INTEGER or ENUMERATED, a valid BIT STRING, an empty NULL, a
      # well-formed OBJECT IDENTIFIER, a UTCTime or GeneralizedTime in its
      # DER form, SEQUENCE and SET constructed and every other universal
      # type primitive. Tags of the other classes are left uninterpreted.
      # For values Beryl keeps without reading, such as the parameters of
      # a key algorithm it does not use. Raises `MalformedEncoding`.
      def check_universal_contents(element : Element) : Nil
        tag = element.tag
        return unless tag.tag_class.universal?

        if tag.number == 16 || tag.number == 17
          enter(element) do |inner|
            until inner.at_end?
              inner.check_universal_contents(inner.read_element)
            end
          end
          return
        end
        malformed("a constructed #{tag}, which DER encodes primitive", element.offset) if tag.is_constructed

        content = element.content
        case tag.number
        when 1
          malformed("a DER BOOLEAN is 0x00 or 0xFF", element.offset) unless content.size == 1 && (content[0] == 0x00 || content[0] == 0xff)
        when 2, 10
          DistinguishedEncodingRules.check_minimal_integer(element)
        when 3
          DistinguishedEncodingRules.decode_bit_string(element)
        when 5
          malformed("a NULL with contents", element.offset) unless content.empty?
        when 6
          DistinguishedEncodingRules.check_object_identifier(element)
        when 23, 24
          DistinguishedEncodingRules.decode_time(element)
        end
      end

      # Yields a reader over *bytes* that sit inside an element read
      # earlier (the contents of an OCTET STRING or BIT STRING that hold
      # DER of their own), one level deeper.
      def enter_encapsulated(element : Element, bytes : Bytes, & : Reader -> T) : T forall T
        encapsulated = Element.new(element.tag, bytes, element.encoded, element.offset)
        inner = Reader.new(encapsulated, @limits, @depth + 1)
        result = yield inner
        inner.finish
        result
      end

      # Reads a BOOLEAN (only `0x00` and `0xFF` are DER).
      def read_boolean(tag : Tag = BOOLEAN) : Bool
        element = read_element(tag)
        content = element.content
        malformed("a BOOLEAN has one content byte", element.offset) unless content.size == 1
        case content[0]
        when 0x00_u8 then false
        when 0xff_u8 then true
        else              malformed("a DER BOOLEAN is 0x00 or 0xFF", element.offset)
        end
      end

      # Reads a NULL.
      def read_null : Nil
        element = read_element(NULL)
        malformed("a NULL has no contents", element.offset) unless element.content.empty?
      end

      # Reads an INTEGER and returns its two's-complement contents, checked
      # to be minimal.
      def read_integer_bytes(tag : Tag = INTEGER) : Bytes
        element = read_element(tag)
        DistinguishedEncodingRules.check_minimal_integer(element)
        element.content
      end

      # Reads an INTEGER that must be zero or positive and returns its
      # magnitude without the sign byte.
      def read_unsigned_integer_bytes(tag : Tag = INTEGER) : Bytes
        element = read_element(tag)
        DistinguishedEncodingRules.check_minimal_integer(element)
        content = element.content
        malformed("the INTEGER is negative", element.offset) if content[0] & 0x80 != 0
        content[0] == 0 && content.size > 1 ? content[1, content.size - 1] : content
      end

      # Reads an INTEGER that fits in an Int64.
      def read_small_integer(tag : Tag = INTEGER) : Int64
        element = read_element(tag)
        DistinguishedEncodingRules.check_minimal_integer(element)
        content = element.content
        malformed("the INTEGER does not fit in 64 bits", element.offset) if content.size > 8
        value = content[0] & 0x80 != 0 ? -1_i64 : 0_i64
        content.each { |byte| value = (value << 8) | byte.to_i64 }
        value
      end

      # Reads an OBJECT IDENTIFIER, checked to be minimal.
      def read_object_identifier : ObjectIdentifier
        element = read_element(OBJECT_IDENTIFIER)
        DistinguishedEncodingRules.check_object_identifier(element)
        ObjectIdentifier.new(element.content)
      end

      # Reads a BIT STRING.
      def read_bit_string(tag : Tag = BIT_STRING) : BitString
        DistinguishedEncodingRules.decode_bit_string(read_element(tag))
      end

      # Reads a BIT STRING that must hold whole bytes, such as a public key
      # or a signature.
      def read_byte_aligned_bit_string(tag : Tag = BIT_STRING) : Bytes
        element = read_element(tag)
        bit_string = DistinguishedEncodingRules.decode_bit_string(element)
        malformed("the BIT STRING must hold whole bytes", element.offset) unless bit_string.unused_bit_count == 0
        bit_string.bytes
      end

      # Reads an OCTET STRING.
      def read_octet_string(tag : Tag = OCTET_STRING) : Bytes
        read_element(tag).content
      end

      # Reads a UTCTime or a GeneralizedTime in the forms RFC 5280 §4.1.2.5
      # allows, and returns it in UTC.
      def read_time : Time
        element = read_element
        DistinguishedEncodingRules.decode_time(element)
      end

      private def read_tag : Tag
        first = next_byte
        tag_class = TagClass.new((first >> 6) & 0x03)
        is_constructed = first & 0x20 != 0
        number = (first & 0x1f).to_u32
        if number == 0x1f
          # The high-tag-number form (X.690 §8.1.2.4): base-128 groups, the
          # first never 0x80, the number at least 31, here at most 4 groups.
          number = 0_u32
          group_count = 0
          loop do
            byte = next_byte
            malformed("a tag number has a leading zero group") if group_count == 0 && byte == 0x80
            group_count += 1
            malformed("a tag number longer than 4 groups") if group_count > 4
            number = (number << 7) | (byte & 0x7f)
            break if byte & 0x80 == 0
          end
          malformed("a tag number below 31 in the long form") if number < 31
        end
        Tag.new(tag_class, is_constructed, number)
      end

      private def read_length : Int32
        first = next_byte
        return first.to_i32 if first < 0x80

        malformed("an indefinite length (BER, not DER)") if first == 0x80
        length_bytesize = first & 0x7f
        malformed("a length of #{length_bytesize} bytes") if length_bytesize > 4
        length = 0_i64
        length_bytesize.times do |index|
          byte = next_byte
          malformed("a length with a leading zero byte") if index == 0 && byte == 0
          length = (length << 8) | byte.to_i64
        end
        malformed("a length under 128 in the long form") if length < 0x80
        malformed("a length past the input") if length > Int32::MAX
        length.to_i32
      end

      private def next_byte : UInt8
        malformed("the input ended inside an element header") if at_end?
        byte = @bytes[@position]
        @position += 1
        byte
      end

      private def malformed(reason : String, at position : Int32 = @position) : NoReturn
        raise MalformedEncoding.new(reason, @base_offset + position)
      end
    end

    # :nodoc:
    def self.check_minimal_integer(element : Element) : Nil
      content = element.content
      raise MalformedEncoding.new("an INTEGER has no contents", element.offset) if content.empty?
      return if content.size == 1

      if (content[0] == 0x00 && content[1] & 0x80 == 0) || (content[0] == 0xff && content[1] & 0x80 != 0)
        raise MalformedEncoding.new("the INTEGER is not in its shortest form", element.offset)
      end
    end

    # :nodoc:
    def self.check_object_identifier(element : Element) : Nil
      content = element.content
      raise MalformedEncoding.new("an OBJECT IDENTIFIER has no contents", element.offset) if content.empty?
      raise MalformedEncoding.new("an OBJECT IDENTIFIER ends inside an arc", element.offset) if content[-1] & 0x80 != 0

      is_arc_start = true
      group_count = 0
      content.each do |byte|
        if is_arc_start && byte == 0x80
          raise MalformedEncoding.new("an OBJECT IDENTIFIER arc has a leading zero group", element.offset)
        end
        group_count += 1
        # 9 groups hold 63 bits; longer arcs are not used by anything Beryl reads.
        raise MalformedEncoding.new("an OBJECT IDENTIFIER arc longer than 63 bits", element.offset) if group_count > 9
        is_arc_start = byte & 0x80 == 0
        group_count = 0 if is_arc_start
      end
    end

    # :nodoc:
    def self.decode_bit_string(element : Element) : BitString
      content = element.content
      raise MalformedEncoding.new("a BIT STRING has no contents", element.offset) if content.empty?

      unused_bit_count = content[0].to_i32
      raise MalformedEncoding.new("a BIT STRING with more than 7 unused bits", element.offset) if unused_bit_count > 7

      bytes = content[1, content.size - 1]
      if bytes.empty?
        raise MalformedEncoding.new("an empty BIT STRING with unused bits", element.offset) unless unused_bit_count == 0
      elsif unused_bit_count > 0 && bytes[-1] & ((1 << unused_bit_count) - 1) != 0
        raise MalformedEncoding.new("a BIT STRING whose unused bits are not zero", element.offset)
      end
      BitString.new(bytes, unused_bit_count)
    end

    # :nodoc:
    def self.decode_time(element : Element) : Time
      content = element.content
      if element.tag == UTC_TIME
        # YYMMDDHHMMSSZ; YY of 50 and above is 19YY (RFC 5280 §4.1.2.5.1).
        raise MalformedEncoding.new("a UTCTime is YYMMDDHHMMSSZ", element.offset) unless content.size == 13 && content[12] == 'Z'.ord
        two_digit_year = decimal(element, 0, 2)
        year = two_digit_year >= 50 ? 1900 + two_digit_year : 2000 + two_digit_year
        fields_at = 2
      elsif element.tag == GENERALIZED_TIME
        raise MalformedEncoding.new("a GeneralizedTime is YYYYMMDDHHMMSSZ", element.offset) unless content.size == 15 && content[14] == 'Z'.ord
        year = decimal(element, 0, 4)
        fields_at = 4
      else
        raise MalformedEncoding.new("expected UTCTime or GeneralizedTime, found #{element.tag}", element.offset)
      end

      month = decimal(element, fields_at, 2)
      day = decimal(element, fields_at + 2, 2)
      hour = decimal(element, fields_at + 4, 2)
      minute = decimal(element, fields_at + 6, 2)
      second = decimal(element, fields_at + 8, 2)
      unless year >= 1 && 1 <= month <= 12 && 1 <= day <= Time.days_in_month(year, month) && hour <= 23 && minute <= 59 && second <= 59
        raise MalformedEncoding.new("a time field is out of range", element.offset)
      end
      Time.utc(year, month, day, hour, minute, second)
    end

    private def self.decimal(element : Element, at offset : Int32, digit_count : Int32) : Int32
      value = 0
      digit_count.times do |index|
        byte = element.content[offset + index]
        raise MalformedEncoding.new("a time has a character that is not a digit", element.offset) unless '0'.ord <= byte <= '9'.ord
        value = value * 10 + (byte - '0'.ord)
      end
      value
    end
  end

  alias DER = DistinguishedEncodingRules
end
