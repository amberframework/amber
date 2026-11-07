require "../param_constraint"

module Amber::Router::ParamConstraints
  # Matches a segment made only of the given ASCII characters, with a length
  # between `min_length` and `max_length` bytes.
  #
  # ```
  # hex = CharacterRun.new("hex", '0'..'9', 'a'..'f', 'A'..'F')
  # hex.matches?("c0ffee") # => true
  # hex.matches?("coffee") # => false
  #
  # NUMERIC.with_length(3).matches?("042") # => true
  # ```
  struct CharacterRun
    include Amber::Router::ParamConstraint

    getter label : String
    getter min_length : Int32
    getter max_length : Int32?

    # One bit per ASCII code point: bits 0-63 in `@low_bits`, 64-127 in
    # `@high_bits`.
    @low_bits : UInt64
    @high_bits : UInt64

    # Builds a rule from characters and character ranges. Raises
    # `ArgumentError` for a character outside ASCII, an empty range, or
    # lengths that no segment could have.
    def initialize(@label : String, *characters : Char | Range(Char, Char),
                   @min_length : Int32 = 1, @max_length : Int32? = nil)
      low_bits = 0_u64
      high_bits = 0_u64
      characters.each do |entry|
        codes = entry.is_a?(Char) ? entry.ord..entry.ord : Range.new(entry.begin.ord, entry.end.ord, entry.excludes_end?)
        raise ArgumentError.new("#{@label}: #{entry.inspect} is empty") if codes.empty?
        raise ArgumentError.new("#{@label}: #{entry.inspect} is outside ASCII") if codes.max >= 128
        codes.each do |code|
          if code < 64
            low_bits |= 1_u64 << code
          else
            high_bits |= 1_u64 << (code - 64)
          end
        end
      end
      @low_bits = low_bits
      @high_bits = high_bits
      validate_lengths
    end

    protected def initialize(@label : String, @low_bits : UInt64, @high_bits : UInt64,
                             @min_length : Int32, @max_length : Int32?)
      validate_lengths
    end

    private def validate_lengths : Nil
      raise ArgumentError.new("#{@label}: min_length #{@min_length} is negative") if @min_length < 0
      if maximum = @max_length
        raise ArgumentError.new("#{@label}: max_length #{maximum} is below min_length #{@min_length}") if maximum < @min_length
      end
    end

    # Returns a copy of this rule that accepts exactly *length* characters.
    def with_length(length : Int32) : CharacterRun
      with_length(length, length)
    end

    # Returns a copy of this rule that accepts *min* to *max* characters; a
    # `nil` *max* leaves the length unbounded.
    def with_length(min : Int32, max : Int32?) : CharacterRun
      CharacterRun.new(@label, @low_bits, @high_bits, min, max)
    end

    def matches?(segment : String) : Bool
      matches_bytes?(segment.to_slice)
    end

    def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
      matches_bytes?(path.to_slice[byte_offset, bytesize])
    end

    private def matches_bytes?(bytes : Bytes) : Bool
      return false if bytes.size < @min_length
      if maximum = @max_length
        return false if bytes.size > maximum
      end
      bytes.all? { |byte| includes_byte?(byte) }
    end

    @[AlwaysInline]
    private def includes_byte?(byte : UInt8) : Bool
      if byte < 64
        @low_bits.bit(byte) == 1
      elsif byte < 128
        @high_bits.bit(byte - 64) == 1
      else
        false
      end
    end

    def to_s(io : IO) : Nil
      io << @label
      maximum = @max_length
      return if @min_length == 1 && maximum.nil?
      io << '{' << @min_length
      if maximum != @min_length
        io << ','
        io << maximum if maximum
      end
      io << '}'
    end
  end
end
