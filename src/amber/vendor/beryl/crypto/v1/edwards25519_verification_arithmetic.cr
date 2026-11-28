require "../field_arithmetic"
require "../processor_features"
require "./edwards25519_group"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # [s]B + [k]P on edwards25519 for signature verification, where every
  # input is public, so the time may depend on the scalars: the method of
  # ref10's `ge_double_scalarmult_vartime` (Bernstein, Duif, Lange, Schwabe
  # and Yang, "High-speed high-security signatures", 2011, §4) with wider
  # windows. Both scalars are written in width-w non-adjacent form, w = 8
  # for the base point (its 64 odd multiples 1B, 3B, ..., 127B are a
  # constant affine table) and w = 5 for P (8 odd multiples, built per
  # call); one shared run of doublings goes from the top digit down, and
  # each nonzero digit adds or subtracts its multiple.
  #
  # The points are those of ref10: extended (X : Y : Z : T), "completed"
  # ((X : Z), (Y : T)) as each doubling or addition returns them, and two
  # forms of a multiple ready to add, cached (Y + X, Y - X, Z, 2d·T) and
  # affine (y + x, y - x, 2d·x·y). A doubling that another doubling follows
  # skips T (3 multiplications to leave the completed form instead of 4).
  # The coordinates are four 64-bit words
  # (`FieldArithmetic::Curve25519SolinasFieldWithAssembly`), on the
  # assembly of this processor.
  module Edwards25519VerificationArithmetic
    private alias Words = FieldArithmetic::Curve25519SolinasFieldWithAssembly::Limbs
    private alias Solinas = FieldArithmetic::Curve25519SolinasFieldWithAssembly

    record ExtendedPoint, x : Words, y : Words, z : Words, t : Words
    record CompletedPoint, x : Words, y : Words, z : Words, t : Words
    record CachedPoint, y_plus_x : Words, y_minus_x : Words, z : Words, t_2d : Words
    record AffineNielsPoint, y_plus_x : Words, y_minus_x : Words, xy_2d : Words

    # Returns the words of a `Curve25519FieldElement`.
    def self.words_of(element : Curve25519FieldElement) : Words
      Solinas.from_bytes(element.to_bytes)
    end

    # 2d, as words.
    DOUBLED_CURVE_CONSTANT_WORDS = words_of(Edwards25519Group.doubled_curve_constant)

    # (y + x, y - x, 2d·x·y) of 1B, 3B, 5B, ..., 127B, built once from the
    # group's own arithmetic and reduced to affine coordinates.
    BASE_POINT_ODD_MULTIPLES = begin
      base = Edwards25519Group.base_point
      twice_base = base.double
      list_of_multiples = Array(AffineNielsPoint).new(64)
      multiple = base
      64.times do
        inverse_z = multiple.z.invert
        affine_x = multiple.x * inverse_z
        affine_y = multiple.y * inverse_z
        list_of_multiples << AffineNielsPoint.new(words_of(affine_y + affine_x), words_of(affine_y - affine_x),
          words_of(affine_x * affine_y * Edwards25519Group.doubled_curve_constant))
        multiple = multiple.add(twice_base)
      end
      list_of_multiples
    end

    # The width-*width* non-adjacent form of the 256-bit little-endian
    # *scalar*: digit i weighs 2^i, every nonzero digit is odd and below
    # 2^(width - 1) in size, and of any *width* digits in a row at most
    # one is nonzero. Public scalars only.
    def self.non_adjacent_form(scalar : Bytes, width : Int32) : StaticArray(Int8, 257)
      words = StaticArray(UInt64, 5).new(0_u64)
      32.times { |index| words[index >> 3] |= scalar[index].to_u64 << (8 * (index & 7)) }
      digits = StaticArray(Int8, 257).new(0_i8)
      window_mask = (1_u64 << width) - 1
      half_window = 1_i64 << (width - 1)
      position = 0
      while position < 257
        if words[0].odd?
          digit = (words[0] & window_mask).to_i64
          digit -= 1_i64 << width if digit >= half_window
          digits[position] = digit.to_i8
          if digit > 0
            borrow = digit.to_u64
            5.times do |index|
              before = words[index]
              words[index] = before &- borrow
              borrow = before < borrow ? 1_u64 : 0_u64
            end
          else
            carry = (-digit).to_u64
            5.times do |index|
              words[index] = words[index] &+ carry
              carry = words[index] < carry ? 1_u64 : 0_u64
            end
          end
        end
        4.times { |index| words[index] = (words[index] >> 1) | (words[index + 1] << 63) }
        words[4] >>= 1
        position += 1
      end
      digits
    end

    # Returns the encoding of [first_scalar]B + [second_scalar]*point*
    # (both scalars 32 little-endian bytes), in variable time.
    def self.multiply_and_add_encoded(first_scalar : Bytes, point : Edwards25519Group::Point, second_scalar : Bytes) : Bytes
      {% if flag?(:aarch64) && !flag?(:beryl_portable_curves) %}
        multiply_and_add_encoded(Solinas::AArch64, first_scalar, point, second_scalar)
      {% elsif flag?(:x86_64) && !flag?(:beryl_portable_curves) %}
        if ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
          multiply_and_add_encoded(Solinas::X86WithWideMultiply, first_scalar, point, second_scalar)
        else
          multiply_and_add_encoded(Solinas::X86WithMultiply, first_scalar, point, second_scalar)
        end
      {% else %}
        multiply_and_add_encoded(Solinas::Portable, first_scalar, point, second_scalar)
      {% end %}
    end

    # `multiply_and_add_encoded` on the field variant *field*.
    def self.multiply_and_add_encoded(field : F.class, first_scalar : Bytes, point : Edwards25519Group::Point, second_scalar : Bytes) : Bytes forall F
      first_digits = non_adjacent_form(first_scalar, 8)
      second_digits = non_adjacent_form(second_scalar, 5)
      base_multiples = BASE_POINT_ODD_MULTIPLES

      extended = ExtendedPoint.new(words_of(point.x), words_of(point.y), words_of(point.z), words_of(point.t))
      twice = to_extended(field, double(field, extended.x, extended.y, extended.z))
      list_of_point_multiples = Array(CachedPoint).new(8)
      multiple = extended
      8.times do |index|
        list_of_point_multiples << cached(field, multiple)
        multiple = to_extended(field, add(field, multiple, cached(field, twice), false)) if index < 7
      end

      top = 256
      while top >= 0 && first_digits[top] == 0 && second_digits[top] == 0
        top -= 1
      end
      zero = Words.new(0_u64)
      one = Words.new { |index| index == 0 ? 1_u64 : 0_u64 }
      # The neutral element (0 : 1 : 1), projective; T is formed only
      # where an addition needs it.
      x, y, z = zero, one, one
      top.downto(0) do |position|
        completed = double(field, x, y, z)
        first_digit = first_digits[position]
        second_digit = second_digits[position]
        if first_digit != 0 || second_digit != 0
          sum = to_extended(field, completed)
          if first_digit != 0
            completed = add_affine(field, sum, base_multiples[first_digit.abs >> 1], first_digit < 0)
            sum = to_extended(field, completed) if second_digit != 0
          end
          if second_digit != 0
            completed = add(field, sum, list_of_point_multiples[second_digit.abs >> 1], second_digit < 0)
          end
        end
        x = field.mul(completed.x, completed.t)
        y = field.mul(completed.y, completed.z)
        z = field.mul(completed.z, completed.t)
      end
      encode(field, x, y, z)
    end

    # The 32-byte encoding of (X : Y : Z): y with the low bit of x on top.
    def self.encode(field : F.class, x : Words, y : Words, z : Words) : Bytes forall F
      inverse_z = FieldArithmetic::DivstepInversion.invert(Solinas.canonical(z), DIVSTEP_MODULUS)
      affine_x = Solinas.canonical(field.mul(x, inverse_z))
      encoded = Solinas.to_bytes(Solinas.canonical(field.mul(y, inverse_z)))
      encoded[31] |= ((affine_x[0] & 1_u64) << 7).to_u8!
      Bytes.new(32) { |index| encoded[index] }
    end

    private DIVSTEP_MODULUS = FieldArithmetic::DivstepInversion.modulus_of(Solinas::PRIME_WORDS)

    # ref10's `ge_p2_dbl`: 2·(X : Y : Z), completed, from four squarings.
    @[AlwaysInline]
    def self.double(field : F.class, x : Words, y : Words, z : Words) : CompletedPoint forall F
      xx = field.square(x)
      yy = field.square(y)
      twice_zz = field.square(z)
      twice_zz = field.add(twice_zz, twice_zz)
      sum_squared = field.square(field.add(x, y))
      new_y = field.add(yy, xx)
      new_z = field.sub(yy, xx)
      CompletedPoint.new(field.sub(sum_squared, new_y), new_y, new_z, field.sub(twice_zz, new_z))
    end

    @[AlwaysInline]
    def self.to_extended(field : F.class, point : CompletedPoint) : ExtendedPoint forall F
      ExtendedPoint.new(field.mul(point.x, point.t), field.mul(point.y, point.z), field.mul(point.z, point.t), field.mul(point.x, point.y))
    end

    @[AlwaysInline]
    def self.cached(field : F.class, point : ExtendedPoint) : CachedPoint forall F
      CachedPoint.new(field.add(point.y, point.x), field.sub(point.y, point.x), point.z, field.mul(point.t, DOUBLED_CURVE_CONSTANT_WORDS))
    end

    # ref10's `ge_add` (or `ge_sub` when *subtract*): *point* ± *other*.
    @[AlwaysInline]
    def self.add(field : F.class, point : ExtendedPoint, other : CachedPoint, subtract : Bool) : CompletedPoint forall F
      first = subtract ? other.y_minus_x : other.y_plus_x
      second = subtract ? other.y_plus_x : other.y_minus_x
      a = field.mul(field.add(point.y, point.x), first)
      b = field.mul(field.sub(point.y, point.x), second)
      c = field.mul(other.t_2d, point.t)
      zz = field.mul(point.z, other.z)
      d = field.add(zz, zz)
      if subtract
        CompletedPoint.new(field.sub(a, b), field.add(a, b), field.sub(d, c), field.add(d, c))
      else
        CompletedPoint.new(field.sub(a, b), field.add(a, b), field.add(d, c), field.sub(d, c))
      end
    end

    # ref10's `ge_madd` (or `ge_msub`): *point* ± an affine multiple.
    @[AlwaysInline]
    def self.add_affine(field : F.class, point : ExtendedPoint, other : AffineNielsPoint, subtract : Bool) : CompletedPoint forall F
      first = subtract ? other.y_minus_x : other.y_plus_x
      second = subtract ? other.y_plus_x : other.y_minus_x
      a = field.mul(field.add(point.y, point.x), first)
      b = field.mul(field.sub(point.y, point.x), second)
      c = field.mul(other.xy_2d, point.t)
      d = field.add(point.z, point.z)
      if subtract
        CompletedPoint.new(field.sub(a, b), field.add(a, b), field.sub(d, c), field.add(d, c))
      else
        CompletedPoint.new(field.sub(a, b), field.add(a, b), field.add(d, c), field.sub(d, c))
      end
    end
  end
end
