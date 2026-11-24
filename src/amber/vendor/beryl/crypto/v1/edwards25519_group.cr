require "random/secure"
require "../field_arithmetic"
require "../constant_time_selection"
require "../secret_wiping"
require "./curve25519_field_element"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # The group of edwards25519 (RFC 8032 §5.1) and its scalars modulo the
  # group order L. Points are in extended coordinates (X : Y : Z : T) with
  # x = X/Z, y = Y/Z and x*y = T/Z; the addition and doubling formulas are
  # RFC 8032 §5.1.4's, which are complete on this curve (they give the right
  # answer for every pair of points, the neutral element included).
  module Edwards25519Group
    private alias FieldElement = Curve25519FieldElement
    private alias ScalarField = Amber::Beryl::Crypto::FieldArithmetic::Curve25519ScalarField

    ENCODED_BYTESIZE = 32

    # L = 2^252 + 27742317777372353535851937790883648493, little-endian.
    GROUP_ORDER = Bytes[
      0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
    ]

    # The base point B: y = 4/5 with x even (RFC 8032 §5.1).
    BASE_POINT_ENCODING = Bytes.new(ENCODED_BYTESIZE) { |index| index == 0 ? 0x58_u8 : 0x66_u8 }

    # d = -121665/121666.
    CURVE_CONSTANT = begin
      -FieldElement.from_small(121_665_u64) * FieldElement.from_small(121_666_u64).invert
    end

    def self.curve_constant : FieldElement
      CURVE_CONSTANT
    end

    DOUBLED_CURVE_CONSTANT = curve_constant + curve_constant

    def self.doubled_curve_constant : FieldElement
      DOUBLED_CURVE_CONSTANT
    end

    # sqrt(-1) = 2^((p - 1) / 4).
    SQUARE_ROOT_OF_MINUS_ONE = begin
      # (p - 1) / 4 = 2^253 - 5: 2^((p-5)/8) squared, times 2^... computed as
      # 2^(2^252 - 3) squared (2^253 - 6) times 2.
      two = FieldElement.from_small(2_u64)
      two.power_two_to_252_minus_three.square * two
    end

    def self.square_root_of_minus_one : FieldElement
      SQUARE_ROOT_OF_MINUS_ONE
    end

    BASE_POINT = begin
      decoded = Point.decode(BASE_POINT_ENCODING)
      raise Error.new("the edwards25519 base point failed to decode") unless decoded
      decoded
    end

    def self.base_point : Point
      BASE_POINT
    end

    # The multiples 0B, 1B, ..., 15B, for the fixed window of `multiply_base`.
    BASE_POINT_MULTIPLES = begin
      multiples = StaticArray(Point, 16).new(Point.neutral)
      1.upto(15) { |index| multiples[index] = multiples[index - 1].add(base_point) }
      multiples
    end

    def self.base_point_multiples : StaticArray(Point, 16)
      BASE_POINT_MULTIPLES
    end

    # For each 4-bit window of a scalar, the 16 multiples of B that window
    # can add: entry j of table i is [j * 16^i]B (little-endian windows).
    # Built once, on first use.
    BASE_POINT_WINDOW_TABLES = begin
      list_of_tables = Array(StaticArray(Point, 16)).new(64)
      base = base_point
      64.times do
        multiples = StaticArray(Point, 16).new(Point.neutral)
        1.upto(15) { |index| multiples[index] = multiples[index - 1].add(base) }
        list_of_tables << multiples
        4.times { base = base.double }
      end
      list_of_tables
    end

    def self.base_point_window_tables : Array(StaticArray(Point, 16))
      BASE_POINT_WINDOW_TABLES
    end

    struct Point
      getter x : FieldElement
      getter y : FieldElement
      getter z : FieldElement
      getter t : FieldElement

      def initialize(@x : FieldElement, @y : FieldElement, @z : FieldElement, @t : FieldElement)
      end

      def self.neutral : self
        new(FieldElement.zero, FieldElement.one, FieldElement.one, FieldElement.zero)
      end

      # Decodes 32 bytes (RFC 8032 §5.1.3). Returns nil when y is not below
      # p, when no x fits, or when x = 0 comes with the sign bit set. The
      # input is public, so the verdict may branch.
      def self.decode(encoded : Bytes) : self?
        return nil unless encoded.size == ENCODED_BYTESIZE
        return nil unless canonical_y?(encoded)

        sign_bit = (encoded[31] >> 7).to_u64
        y = FieldElement.from_bytes(encoded)
        y_squared = y.square
        u = y_squared - FieldElement.one
        v = Edwards25519Group.curve_constant * y_squared + FieldElement.one
        v_cubed = v.square * v
        candidate = u * v_cubed * (u * v_cubed.square * v).power_two_to_252_minus_three
        v_times_candidate_squared = v * candidate.square
        if v_times_candidate_squared.equal_bit(u) == 0_u64
          return nil unless v_times_candidate_squared.equal_bit(-u) == 1_u64

          candidate = candidate * Edwards25519Group.square_root_of_minus_one
        end
        return nil if candidate.zero_bit == 1_u64 && sign_bit == 1_u64

        candidate = -candidate if candidate.low_bit != sign_bit
        new(candidate, y, FieldElement.one, candidate * y)
      end

      # Whether the low 255 bits of *encoded* are below p = 2^255 - 19.
      private def self.canonical_y?(encoded : Bytes) : Bool
        top_byte = encoded[31] & 0x7f_u8
        return true if top_byte < 0x7f_u8
        return true unless (1..30).all? { |index| encoded[index] == 0xff_u8 }

        encoded[0] < 0xed_u8
      end

      # Returns the 32-byte encoding: y, with the low bit of x on top.
      def encode : Bytes
        inverse_z = @z.invert
        affine_x = @x * inverse_z
        affine_y = @y * inverse_z
        encoded_y = affine_y.to_bytes
        encoded_y[31] |= (affine_x.low_bit << 7).to_u8!
        Bytes.new(ENCODED_BYTESIZE) { |index| encoded_y[index] }
      end

      # RFC 8032 §5.1.4, add-2008-hwcd-3.
      def add(other : Point) : Point
        a = (@y - @x) * (other.y - other.x)
        b = (@y + @x) * (other.y + other.x)
        c = @t * Edwards25519Group.doubled_curve_constant * other.t
        z_product = @z * other.z
        d = z_product + z_product
        e = b - a
        f = d - c
        g = d + c
        h = b + a
        Point.new(e * f, g * h, f * g, e * h)
      end

      # RFC 8032 §5.1.4, dbl-2008-hwcd.
      def double : Point
        a = @x.square
        b = @y.square
        z_squared = @z.square
        c = z_squared + z_squared
        h = a + b
        e = h - (@x + @y).square
        g = a - b
        f = c + g
        Point.new(e * f, g * h, f * g, e * h)
      end

      def negate : Point
        Point.new(-@x, @y, @z, -@t)
      end

      # Returns *other* when *bit* is 1, else self.
      def select(bit : UInt64, other : Point) : Point
        Point.new(@x.select(bit, other.x), @y.select(bit, other.y), @z.select(bit, other.z), @t.select(bit, other.t))
      end
    end

    # Returns [scalar]B for a 32-byte little-endian *scalar*, in constant
    # time: one addition per 4-bit window from that window's table in
    # `base_point_window_tables`, picked by scanning all 16 entries, and no
    # doubling.
    #
    # The sum starts as the neutral element written (0 : λ : λ : 0) for a
    # random λ (odd and below 2^255, so 0 modulo p only if it equals p, a
    # chance of 2^-254) rather than (0 : 1 : 1 : 0): the same point, so the
    # same result, but a zero nibble no longer adds (0 : 1 : 1 : 0) to the
    # same coordinates window after window. With the all-zero X25519 key
    # (clamped to 2^254, 63 zero nibbles of 64) that ran measurably faster
    # than random keys on an AMD EPYC 9V74 (Zen 4) runner
    # (docs/crypto/public-key.md, "Timing on x86-64").
    def self.multiply_base(scalar : Bytes) : Point
      list_of_tables = base_point_window_tables
      random_bytes = Random::Secure.random_bytes(32)
      random_bytes[0] |= 1_u8
      random_bytes[31] &= 0x7f_u8
      factor = FieldElement.from_bytes(random_bytes)
      SecretWiping.wipe(random_bytes)
      result = Point.new(FieldElement.zero, factor, factor, FieldElement.zero)
      64.times do |window_index|
        nibble = (scalar.unsafe_fetch(window_index >> 1).to_u64 >> ((window_index & 1) * 4)) & 0xf_u64
        table = list_of_tables.unsafe_fetch(window_index)
        selected = Point.neutral
        16.times do |candidate|
          selected = selected.select(ConstantTimeSelection.equal_bit(candidate.to_u64, nibble), table[candidate])
        end
        result = result.add(selected)
      end
      result
    end

    def self.multiply_constant_time(scalar : Bytes, multiples : StaticArray(Point, 16)) : Point
      result = Point.neutral
      63.downto(0) do |window_index|
        4.times { result = result.double } unless window_index == 63
        nibble = (scalar.unsafe_fetch(window_index >> 1).to_u64 >> ((window_index & 1) * 4)) & 0xf_u64
        selected = Point.neutral
        16.times do |candidate|
          selected = selected.select(ConstantTimeSelection.equal_bit(candidate.to_u64, nibble), multiples[candidate])
        end
        result = result.add(selected)
      end
      result
    end

    # Returns [first_scalar]B + [second_scalar]point, in variable time: for
    # signature verification, where every input is public.
    def self.multiply_and_add_public(first_scalar : Bytes, point : Point, second_scalar : Bytes) : Point
      point_multiples = StaticArray(Point, 16).new(Point.neutral)
      1.upto(15) { |index| point_multiples[index] = point_multiples[index - 1].add(point) }
      base_multiples = base_point_multiples
      result = Point.neutral
      63.downto(0) do |window_index|
        4.times { result = result.double } unless window_index == 63
        shift = (window_index & 1) * 4
        first_nibble = (first_scalar[window_index >> 1] >> shift) & 0xf_u8
        second_nibble = (second_scalar[window_index >> 1] >> shift) & 0xf_u8
        result = result.add(base_multiples[first_nibble]) unless first_nibble == 0
        result = result.add(point_multiples[second_nibble]) unless second_nibble == 0
      end
      result
    end

    # Scalars modulo L, in fiat-crypto's Montgomery domain.
    module Scalar
      alias Limbs = ScalarField::Limbs

      # 2^168 in the Montgomery domain: the weight of the middle chunk in
      # `reduce`.
      WEIGHT_OF_SECOND_CHUNK = begin
        limbs = Limbs.new(0_u64)
        limbs[2] = 1_u64 << 40 # 2^(128 + 40)
        ScalarField.to_montgomery(limbs)
      end

      def self.weight_of_second_chunk : Limbs
        WEIGHT_OF_SECOND_CHUNK
      end

      # 2^336 mod L in the Montgomery domain.
      WEIGHT_OF_THIRD_CHUNK = begin
        ScalarField.mul(weight_of_second_chunk, weight_of_second_chunk)
      end

      def self.weight_of_third_chunk : Limbs
        WEIGHT_OF_THIRD_CHUNK
      end

      # Reduces a little-endian number of up to 64 bytes modulo L, in
      # constant time: it is split into chunks of 21, 21 and 22 bytes (each
      # below L), and x mod L = c0 + c1 * 2^168 + c2 * 2^336, all in the
      # Montgomery domain.
      def self.reduce(wide : Bytes) : Limbs
        padded = StaticArray(UInt8, 64).new(0_u8)
        wide.size.times { |index| padded[index] = wide.unsafe_fetch(index) }
        first = ScalarField.to_montgomery(chunk(padded, 0, 21))
        second = ScalarField.to_montgomery(chunk(padded, 21, 21))
        third = ScalarField.to_montgomery(chunk(padded, 42, 22))
        SecretWiping.wipe(padded.to_slice)
        ScalarField.add(first, ScalarField.add(ScalarField.mul(second, weight_of_second_chunk), ScalarField.mul(third, weight_of_third_chunk)))
      end

      private def self.chunk(padded : StaticArray(UInt8, 64), start : Int32, bytesize : Int32) : Limbs
        limbs = Limbs.new(0_u64)
        bytesize.times do |offset|
          limbs[offset >> 3] |= padded[start + offset].to_u64 << ((offset & 7) * 8)
        end
        limbs
      end

      # Returns the canonical 32-byte little-endian encoding.
      def self.encode(scalar : Limbs) : Bytes
        encoded = ScalarField.to_bytes(ScalarField.from_montgomery(scalar))
        Bytes.new(32) { |index| encoded[index] }
      end

      def self.multiply_add(first : Limbs, second : Limbs, addend : Limbs) : Limbs
        ScalarField.add(ScalarField.mul(first, second), addend)
      end

      # Whether a 32-byte little-endian number is below L. Public inputs only.
      def self.canonical?(encoded : Bytes) : Bool
        31.downto(0) do |index|
          return true if encoded[index] < GROUP_ORDER[index]
          return false if encoded[index] > GROUP_ORDER[index]
        end
        false
      end
    end
  end
end
