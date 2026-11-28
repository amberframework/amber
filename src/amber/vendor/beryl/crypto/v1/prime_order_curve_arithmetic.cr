require "../field_arithmetic"
require "../constant_time_selection"
require "../secret_wiping"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # Writes the arithmetic of a short Weierstrass curve y^2 = x^3 - 3x + b of
  # prime order (P-256, P-384) into the module it is called in, on the
  # fiat-crypto field *field* and scalar field *scalar_field*, both in the
  # Montgomery domain on 64-bit words.
  #
  # Points are Jacobian (X : Y : Z), x = X/Z^2, y = Y/Z^3, with infinity
  # marked by Z = 0. Doubling is dbl-2001-b and addition add-1998-cmo-2 of
  # the Explicit-Formulas Database (a = -3), with mixed addition against
  # affine table entries; infinity on either side is handled by masks, and
  # each constant-time caller shows that its two operands are never equal,
  # the one case those formulas get wrong (see `multiply_constant_time` and
  # `multiply_generator`).
  #
  # Constant-time scalar multiplication writes the scalar in signed 5-bit
  # windows (Booth's recoding, as OpenSSL's nistz256 does): a variable
  # point reads all 16 of its multiples each window, the generator all 16
  # entries of one precomputed affine table per window, so [k]G needs no
  # doubling. Verification, whose inputs are public, uses width-7 and
  # width-5 non-adjacent forms and may branch. Inversion and square roots
  # are by divsteps on the 256-bit curves (`DivstepInversion`) and
  # exponentiations by public exponents (Fermat) on P-384, as are square roots.
  #
  # Integers outside the Montgomery domain are big-endian `Bytes` of
  # *bytesize* bytes, as SEC 1 and FIPS 186-5 write them.
  macro define_prime_order_curve_arithmetic(field, scalar_field, bytesize, field_prime, group_order, curve_b, generator_x, generator_y)
    alias Field = {{ field }}
    alias ScalarField = {{ scalar_field }}
    alias Limbs = Field::Limbs

    BYTESIZE       = {{ bytesize }}
    LIMB_COUNT     = {{ bytesize }} // 8
    FIELD_PRIME    = {{ field_prime }}.hexbytes
    GROUP_ORDER    = {{ group_order }}.hexbytes

    # p - 2, (p + 1) / 4 and n - 2, the public exponents of inversion and
    # of the square root (p = 3 mod 4 for both curves).
    FIELD_INVERSE_EXPONENT = big_endian_minus_small(FIELD_PRIME, 2_u8)

    def self.field_inverse_exponent : Bytes
      FIELD_INVERSE_EXPONENT
    end
    SQUARE_ROOT_EXPONENT = big_endian_quarter_of_successor(FIELD_PRIME)

    def self.square_root_exponent : Bytes
      SQUARE_ROOT_EXPONENT
    end
    SCALAR_INVERSE_EXPONENT = big_endian_minus_small(GROUP_ORDER, 2_u8)

    def self.scalar_inverse_exponent : Bytes
      SCALAR_INVERSE_EXPONENT
    end

    CURVE_B = field_element_from_big_endian({{ curve_b }}.hexbytes)
    GENERATOR = begin
      Point.new(field_element_from_big_endian({{ generator_x }}.hexbytes),
        field_element_from_big_endian({{ generator_y }}.hexbytes), Field.set_one)
    end

    def self.generator : Point
      GENERATOR
    end

    # The number of 5-bit signed windows of a scalar: enough for its
    # BYTESIZE * 8 bits and the sign of the top window.
    GENERATOR_WINDOW_COUNT = (BYTESIZE * 8 + 5) // 5

    # For each signed 5-bit window of an odd scalar, counted from the least
    # significant, the multiples of G that window can add, in affine
    # coordinates: entry j of table i is [(2j + 1) * 32^i]G, for j = 0 to
    # 15, the odd multiples 1 to 31 (`odd_digit`). Built once, when first
    # used, with a single inversion.
    GENERATOR_WINDOW_TABLES = begin
      list_of_points = [] of Point
      base = generator
      GENERATOR_WINDOW_COUNT.times do
        twice_base = base.double
        multiple = base
        16.times do
          list_of_points << multiple
          multiple = multiple.add_public(twice_base)
        end
        5.times { base = base.double }
      end
      list_of_affine = to_affine_together(list_of_points)
      Array(StaticArray(AffinePoint, 16)).new(GENERATOR_WINDOW_COUNT) do |window|
        StaticArray(AffinePoint, 16).new { |index| list_of_affine[window * 16 + index] }
      end
    end

    def self.generator_window_tables : Array(StaticArray(AffinePoint, 16))
      GENERATOR_WINDOW_TABLES
    end

    # The odd multiples G, 3G, ..., 63G in affine coordinates, for the
    # width-7 signed digits of signature verification.
    GENERATOR_ODD_MULTIPLES = begin
      list_of_points = [] of Point
      twice_generator = generator.double
      current = generator
      32.times do
        list_of_points << current
        current = current.add_public(twice_generator)
      end
      to_affine_together(list_of_points)
    end

    def self.generator_odd_multiples : Array(AffinePoint)
      GENERATOR_ODD_MULTIPLES
    end

    # Returns *value* - *small* for a big-endian *value* larger than *small*.
    def self.big_endian_minus_small(value : Bytes, small : UInt8) : Bytes
      result = value.dup
      borrow = small.to_i32
      (result.size - 1).downto(0) do |index|
        difference = result[index].to_i32 - borrow
        borrow = difference < 0 ? 1 : 0
        result[index] = (difference & 0xff).to_u8
      end
      result
    end

    # Returns (value + 1) / 4 for a big-endian odd *value*.
    def self.big_endian_quarter_of_successor(value : Bytes) : Bytes
      successor = value.dup
      carry = 1
      (successor.size - 1).downto(0) do |index|
        sum = successor[index].to_i32 + carry
        carry = sum >> 8
        successor[index] = (sum & 0xff).to_u8
      end
      quarter = Bytes.new(successor.size)
      remainder = carry # the bit above the top byte
      successor.size.times do |index|
        current = (remainder << 8) | successor[index].to_i32
        quarter[index] = (current >> 2).to_u8
        remainder = current & 3
      end
      quarter
    end

    # Packs a big-endian integer (below the modulus) into fiat-crypto limbs,
    # outside the Montgomery domain.
    def self.limbs_from_big_endian(encoded : Bytes) : Limbs
      limbs = Limbs.new(0_u64)
      BYTESIZE.times do |offset|
        byte = encoded.unsafe_fetch(BYTESIZE - 1 - offset).to_u64
        limbs[offset >> 3] |= byte << ((offset & 7) * 8)
      end
      limbs
    end

    def self.limbs_to_big_endian(limbs : Limbs) : Bytes
      Bytes.new(BYTESIZE) do |index|
        offset = BYTESIZE - 1 - index
        (limbs[offset >> 3] >> ((offset & 7) * 8)).to_u8!
      end
    end

    def self.field_element_from_big_endian(encoded : Bytes) : Limbs
      Field.to_montgomery(limbs_from_big_endian(encoded))
    end

    def self.field_element_to_big_endian(element : Limbs) : Bytes
      limbs_to_big_endian(Field.from_montgomery(element))
    end

    # Returns 1 when the big-endian *encoded* is below *modulus*, else 0.
    def self.below_bit(encoded : Bytes, modulus : Bytes) : UInt64
      ConstantTimeSelection.big_endian_less_than_bit(encoded, modulus)
    end

    # Reduces a big-endian integer below 2^(8 * BYTESIZE) modulo the group
    # order n by one conditional subtraction (2^(8 * BYTESIZE) < 2n for both
    # curves), in constant time; the result is outside the Montgomery domain.
    def self.reduce_once_modulo_order(encoded : Bytes) : Limbs
      value = limbs_from_big_endian(encoded)
      order = limbs_from_big_endian(GROUP_ORDER)
      difference = Limbs.new(0_u64)
      borrow = 0_u64
      LIMB_COUNT.times do |index|
        limb, borrow = Field.subborrowx_u64(borrow, value[index], order[index])
        difference[index] = limb
      end
      # Keep the difference unless the subtraction borrowed.
      Field.selectznz(borrow, difference, value)
    end

    # Bit *position* (0 = least significant) of the big-endian *exponent*.
    @[AlwaysInline]
    def self.exponent_bit(exponent : Bytes, position : Int32) : Int32
      ((exponent[exponent.size - 1 - (position >> 3)] >> (position & 7)) & 1).to_i32
    end

    # Raises *base* to the public big-endian *exponent* in the field
    # *field* (the field prime's or the group order's), by sliding windows
    # of up to five bits: the odd powers base^1, base^3, ..., base^31 come
    # first, then each window costs its squarings and one multiplication.
    # The steps depend only on the exponent, which is public.
    def self.power_by_public_exponent(field, base : Limbs, exponent : Bytes) : Limbs
      odd_powers = StaticArray(Limbs, 16).new(base)
      base_squared = field.square(base)
      1.upto(15) { |index| odd_powers[index] = field.mul(odd_powers[index - 1], base_squared) }
      bit_count = exponent.size * 8
      result = field.set_one
      position = bit_count - 1
      while position >= 0 && exponent_bit(exponent, position) == 0
        position -= 1
      end
      started = false
      while position >= 0
        if exponent_bit(exponent, position) == 0
          result = field.square(result)
          position -= 1
          next
        end
        low = Math.max(position - 4, 0)
        while exponent_bit(exponent, low) == 0
          low += 1
        end
        window = 0
        position.downto(low) { |bit| window = (window << 1) | exponent_bit(exponent, bit) }
        if started
          (position - low + 1).times { result = field.square(result) }
          result = field.mul(result, odd_powers[window >> 1])
        else
          result = odd_powers[window >> 1]
          started = true
        end
        position = low - 1
      end
      result
    end

    # Raises *base* (Montgomery domain of the field prime) to the public
    # big-endian *exponent*.
    def self.field_power(base : Limbs, exponent : Bytes) : Limbs
      power_by_public_exponent(Field, base, exponent)
    end

    # `field_power` modulo the group order.
    def self.scalar_power(base : Limbs, exponent : Bytes) : Limbs
      power_by_public_exponent(ScalarField, base, exponent)
    end

    {% if bytesize == 32 %}
      # The field prime and the group order for `DivstepInversion`, and
      # R^3 modulo each (R = 2^256): the inverse of a·R, as an integer, is
      # a^-1·R^-1, and its Montgomery product with R^3 is a^-1·R, the
      # Montgomery form of a^-1.
      FIELD_DIVSTEP_MODULUS  = ::Amber::Beryl::Crypto::FieldArithmetic::DivstepInversion.modulus_of(limbs_from_big_endian(FIELD_PRIME))
      FIELD_R_CUBED          = Field.to_montgomery(Field.to_montgomery(Field.set_one))
      SCALAR_DIVSTEP_MODULUS = ::Amber::Beryl::Crypto::FieldArithmetic::DivstepInversion.modulus_of(limbs_from_big_endian(GROUP_ORDER))
      SCALAR_R_CUBED         = ScalarField.to_montgomery(ScalarField.to_montgomery(ScalarField.set_one))
    {% end %}

    # Returns the inverse of *element* (Montgomery domain of the field
    # prime), or zero for zero, in constant time: by divsteps for 256-bit
    # curves (`DivstepInversion`), by Fermat's exponent p - 2 otherwise.
    def self.field_invert(element : Limbs) : Limbs
      {% if bytesize == 32 %}
        Field.mul(::Amber::Beryl::Crypto::FieldArithmetic::DivstepInversion.invert(element, FIELD_DIVSTEP_MODULUS), FIELD_R_CUBED)
      {% else %}
        field_power(element, field_inverse_exponent)
      {% end %}
    end

    # `field_invert` modulo the group order.
    def self.scalar_invert(element : Limbs) : Limbs
      {% if bytesize == 32 %}
        ScalarField.mul(::Amber::Beryl::Crypto::FieldArithmetic::DivstepInversion.invert(element, SCALAR_DIVSTEP_MODULUS), SCALAR_R_CUBED)
      {% else %}
        scalar_power(element, scalar_inverse_exponent)
      {% end %}
    end

    # Returns 1 when two field elements are equal, else 0.
    def self.field_equal_bit(first : Limbs, second : Limbs) : UInt64
      ConstantTimeSelection.equal_bit(Field.nonzero(Field.sub(first, second)), 0_u64)
    end

    def self.field_zero_bit(element : Limbs) : UInt64
      ConstantTimeSelection.equal_bit(Field.nonzero(element), 0_u64)
    end

    # x^3 - 3x + b.
    def self.curve_right_side(x : Limbs) : Limbs
      x_cubed = Field.mul(Field.square(x), x)
      three_x = Field.add(Field.add(x, x), x)
      Field.add(Field.sub(x_cubed, three_x), CURVE_B)
    end

    # A point in affine coordinates (x, y), both in the Montgomery domain.
    # The tables of multiples of G hold these; the point at infinity has
    # no affine coordinates, and a table entry for it is never read.
    record AffinePoint, x : Limbs, y : Limbs

    # A point in Jacobian coordinates (X : Y : Z), x = X/Z^2, y = Y/Z^3;
    # Z = 0 is the point at infinity. Doubling is the a = -3 formula
    # dbl-2001-b of the Explicit-Formulas Database (3M + 5S); it has no
    # exceptional case on a curve of prime order, where no point has y = 0,
    # and it keeps Z = 0 at infinity. Addition (add-1998-cmo-2, 12M + 4S)
    # and mixed addition with an affine point (8M + 3S) give the right sum
    # for every pair except a point added to itself, where they return
    # infinity; `add` and `add_affine` choose the other operand when one is
    # infinity by mask. The scalar multiplications below never add a point
    # to itself, because a scalar below the group order n never makes two
    # equal operands (each says why); `add_public` and `add_affine_public`,
    # for verification, branch to a doubling instead, which is allowed there
    # because every input is public.
    #
    # The constant-time scalar multiplications never compute on the point
    # at infinity either. The generator multiplication writes its scalar in
    # odd digits, so every window adds a point and its sum is never
    # infinity. The variable-point one keeps a stand-in point in place of a
    # running sum that is still infinity, with a bit that says so, and its
    # digit 0 reads a real multiple whose sum is then dropped by mask. With
    # Z = 0 or a zero table entry as an operand, a scalar with zero windows
    # (the scalar 1 has 51 of 52) ran measurably faster than a random one on
    # AMD EPYC 7763 and 9V74 (Zen 3 and Zen 4) and on Apple M4 with Data
    # Independent Timing off, though no branch or address depended on it
    # (docs/crypto/public-key.md, "Timing on x86-64"). The operands also
    # change every window, because operands that came back unchanged window
    # after window still ran faster there.
    #
    # The prime-order curves of BoringSSL and OpenSSL (`p256.c`,
    # `ecp_nistz256.c`) use the same coordinates and the same argument.
    struct Point
      getter x : Limbs
      getter y : Limbs
      getter z : Limbs

      def initialize(@x : Limbs, @y : Limbs, @z : Limbs)
      end

      def self.neutral : Point
        Point.new(Field.set_one, Field.set_one, Limbs.new(0_u64))
      end

      def self.from_affine(point : AffinePoint) : Point
        Point.new(point.x, point.y, Field.set_one)
      end

      # Returns 1 for the point at infinity, else 0.
      def neutral_bit : UInt64
        ConstantTimeSelection.equal_bit(Field.nonzero(@z), 0_u64)
      end

      # Returns 1 when two field elements are equal, else 0.
      def self.equal_bit(first : Limbs, second : Limbs) : UInt64
        ConstantTimeSelection.equal_bit(Field.nonzero(Field.sub(first, second)), 0_u64)
      end

      # The steps are those of OpenSSL's `ecp_nistz256_point_double`, which
      # compute the same formula with 10 field additions and one halving
      # instead of 14 additions: 4·Y^2 is (2·Y)^2, 8·Y^4 is half of its
      # square, 4·X·Y^2 is X·(2·Y)^2 and 8·X·Y^2 its double.
      def double : Point
        {% if flag?(:x86_64) && !flag?(:beryl_portable_curves) && bytesize == 32 %}
          # P-256 on x86-64: the same steps in one assembly statement.
          input = self
          doubled = uninitialized Point
          scratch = uninitialized StaticArray(UInt64, 80)
          if ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(true,
              pointerof(scratch), pointerof(doubled), 1, input: pointerof(input))
          else
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(false,
              pointerof(scratch), pointerof(doubled), 1, input: pointerof(input))
          end
          return doubled
        {% end %}
        twice_y = Field.add(@y, @y)
        delta = Field.square(@z)
        four_y_squared = Field.square(twice_y)
        y_z = Field.mul(@y, @z)
        new_z = Field.add(y_z, y_z)
        alpha_part = Field.mul(Field.add(@x, delta), Field.sub(@x, delta))
        alpha = Field.add(Field.add(alpha_part, alpha_part), alpha_part)
        eight_y_fourth = Field.half(Field.square(four_y_squared))
        beta_4 = Field.mul(four_y_squared, @x)
        beta_8 = Field.add(beta_4, beta_4)
        new_x = Field.sub(Field.square(alpha), beta_8)
        new_y = Field.sub(Field.mul(Field.sub(beta_4, new_x), alpha), eight_y_fourth)
        Point.new(new_x, new_y, new_z)
      end

      # Five doublings in a row (one window of the variable-point
      # multiplication, where x86-64 P-256 runs its own statements).
      def double_five_times : Point
        point = self
        5.times { point = point.double }
        point
      end

      # The sum with *other*, in constant time, for any pair except a point
      # and itself (which gives infinity).
      def add(other : Point) : Point
        sum = add_unchecked(other)
        sum = sum.replace_if(neutral_bit, other)
        sum.replace_if(other.neutral_bit, self)
      end

      # The sum with the affine *other*, or self when *other_is_neutral* is
      # 1, in constant time, for any pair except a point and itself.
      def add_affine(other : AffinePoint, other_is_neutral : UInt64) : Point
        sum = add_affine_unchecked(other)
        sum = sum.replace_if(neutral_bit, Point.from_affine(other))
        sum.replace_if(other_is_neutral, self)
      end

      # The sum with the affine *other*, neither of them infinity, for any
      # pair at all: when the two are equal, the doubling (computed every
      # time) is kept by mask.
      def add_affine_or_double_unchecked(other : AffinePoint) : Point
        z1_squared = Field.square(@z)
        u2 = Field.mul(other.x, z1_squared)
        s2 = Field.mul(other.y, Field.mul(@z, z1_squared))
        h = Field.sub(u2, @x)
        r = Field.sub(s2, @y)
        are_equal = ConstantTimeSelection.equal_bit(Field.nonzero(h) | Field.nonzero(r), 0_u64)
        finish_addition(@x, @y, h, r, @z).replace_if(are_equal, double)
      end

      # The sum with *other* for public points: branches on infinity and on
      # equal points.
      def add_public(other : Point) : Point
        return other if neutral_bit == 1
        return self if other.neutral_bit == 1

        z1_squared = Field.square(@z)
        z2_squared = Field.square(other.z)
        u1 = Field.mul(@x, z2_squared)
        u2 = Field.mul(other.x, z1_squared)
        s1 = Field.mul(@y, Field.mul(other.z, z2_squared))
        s2 = Field.mul(other.y, Field.mul(@z, z1_squared))
        if Point.equal_bit(u1, u2) == 1
          return Point.equal_bit(s1, s2) == 1 ? double : Point.neutral
        end

        finish_addition(u1, s1, Field.sub(u2, u1), Field.sub(s2, s1), Field.mul(@z, other.z))
      end

      # The sum with the affine *other* for public points.
      def add_affine_public(other : AffinePoint) : Point
        return Point.from_affine(other) if neutral_bit == 1

        z1_squared = Field.square(@z)
        u2 = Field.mul(other.x, z1_squared)
        s2 = Field.mul(other.y, Field.mul(@z, z1_squared))
        if Point.equal_bit(@x, u2) == 1
          return Point.equal_bit(@y, s2) == 1 ? double : Point.neutral
        end

        finish_addition(@x, @y, Field.sub(u2, @x), Field.sub(s2, @y), @z)
      end

      # The sum with *other* by the formula alone: right when neither is
      # infinity and the two are neither equal nor opposite.
      def add_unchecked(other : Point) : Point
        {% if flag?(:x86_64) && !flag?(:beryl_portable_curves) && bytesize == 32 %}
          # P-256 on x86-64: the same steps in one assembly statement.
          sum = self
          second = other
          scratch = uninitialized StaticArray(UInt64, 80)
          if ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(true,
              pointerof(scratch), pointerof(sum), 0, other: pointerof(second))
          else
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(false,
              pointerof(scratch), pointerof(sum), 0, other: pointerof(second))
          end
          return sum
        {% end %}
        z1_squared = Field.square(@z)
        z2_squared = Field.square(other.z)
        u1 = Field.mul(@x, z2_squared)
        u2 = Field.mul(other.x, z1_squared)
        s1 = Field.mul(@y, Field.mul(other.z, z2_squared))
        s2 = Field.mul(other.y, Field.mul(@z, z1_squared))
        finish_addition(u1, s1, Field.sub(u2, u1), Field.sub(s2, s1), Field.mul(@z, other.z))
      end

      # The sum with the affine *other* by the formula alone, under the same
      # conditions as `add_unchecked`.
      def add_affine_unchecked(other : AffinePoint) : Point
        z1_squared = Field.square(@z)
        u2 = Field.mul(other.x, z1_squared)
        s2 = Field.mul(other.y, Field.mul(@z, z1_squared))
        finish_addition(@x, @y, Field.sub(u2, @x), Field.sub(s2, @y), @z)
      end

      # X3 = R^2 - H^3 - 2·U1·H^2, Y3 = R·(U1·H^2 - X3) - S1·H^3,
      # Z3 = Z1·Z2·H, from U1 = X1·Z2^2, S1 = Y1·Z2^3, H = U2 - U1 and
      # R = S2 - S1.
      @[AlwaysInline]
      private def finish_addition(u1 : Limbs, s1 : Limbs, h : Limbs, r : Limbs, z1_z2 : Limbs) : Point
        {% if flag?(:x86_64) && !flag?(:beryl_portable_curves) && bytesize == 32 %}
          # P-256 on x86-64: the same steps in one assembly statement.
          inputs = StaticArray[u1, s1, h, r, z1_z2]
          scratch = uninitialized StaticArray(UInt64, 32)
          if ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_finish_addition_statement(true,
              pointerof(scratch), pointerof(inputs))
          else
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_finish_addition_statement(false,
              pointerof(scratch), pointerof(inputs))
          end
          return (pointerof(scratch).as(UInt64*) + 20).as(Point*).value
        {% end %}
        h_squared = Field.square(h)
        h_cubed = Field.mul(h, h_squared)
        v = Field.mul(u1, h_squared)
        new_x = Field.sub(Field.sub(Field.square(r), h_cubed), Field.add(v, v))
        new_y = Field.sub(Field.mul(r, Field.sub(v, new_x)), Field.mul(s1, h_cubed))
        Point.new(new_x, new_y, Field.mul(z1_z2, h))
      end

      def negate : Point
        Point.new(@x, Field.opp(@y), @z)
      end

      # Returns *other* when *bit* is 1, else self.
      def replace_if(bit : UInt64, other : Point) : Point
        Point.new(Field.selectznz(bit, @x, other.x), Field.selectznz(bit, @y, other.y), Field.selectznz(bit, @z, other.z))
      end
    end

    # Returns 1 for the neutral element, else 0.
    def self.neutral_bit(point : Point) : UInt64
      field_zero_bit(point.z)
    end

    # Returns the affine coordinates of *point* in the Montgomery domain.
    # The neutral element has none; its result is (0, 0).
    def self.to_affine(point : Point) : {Limbs, Limbs}
      inverse_z = field_invert(point.z)
      inverse_z_squared = Field.square(inverse_z)
      {Field.mul(point.x, inverse_z_squared), Field.mul(point.y, Field.mul(inverse_z, inverse_z_squared))}
    end

    # The affine x coordinate of *point* alone (ECDH and ECDSA need no y).
    def self.to_affine_x(point : Point) : Limbs
      Field.mul(point.x, Field.square(field_invert(point.z)))
    end

    # The affine form of each point of *list_of_points* (public, none at
    # infinity except where an entry is never read), with one inversion
    # for all of them (Montgomery's trick).
    def self.to_affine_together(list_of_points : Array(Point)) : Array(AffinePoint)
      one = Field.set_one
      list_of_prefix_products = Array(Limbs).new(list_of_points.size)
      running = one
      list_of_points.each do |point|
        list_of_prefix_products << running
        running = Field.mul(running, point.z) unless neutral_bit(point) == 1
      end
      inverse = field_invert(running)
      list_of_affine = Array(AffinePoint).new(list_of_points.size, AffinePoint.new(Limbs.new(0_u64), Limbs.new(0_u64)))
      (list_of_points.size - 1).downto(0) do |index|
        point = list_of_points[index]
        next if neutral_bit(point) == 1

        inverse_z = Field.mul(inverse, list_of_prefix_products[index])
        inverse = Field.mul(inverse, point.z)
        inverse_z_squared = Field.square(inverse_z)
        list_of_affine[index] = AffinePoint.new(Field.mul(point.x, inverse_z_squared),
          Field.mul(point.y, Field.mul(inverse_z, inverse_z_squared)))
      end
      list_of_affine
    end

    # P, 2P, ..., 16P (entry j - 1 is [j]P). Each odd entry is the one
    # before it plus P; the two are never equal, since [i]P = P would need
    # i = 1 mod n, and the group order n is far above 16. Each even entry
    # is a doubling.
    def self.multiples_of(point : Point) : StaticArray(Point, 16)
      multiples = StaticArray(Point, 16).new(point)
      2.upto(16) do |multiple|
        multiples[multiple - 1] = multiple.even? ? multiples[multiple // 2 - 1].double : multiples[multiple - 2].add(point)
      end
      multiples
    end

    # `multiples_of` for a point given in affine coordinates (Z = 1), as a
    # decoded public key is: each odd entry is a mixed addition of P
    # (8M + 3S rather than 12M + 4S), with the same argument that its two
    # operands differ.
    def self.multiples_of_affine(point : AffinePoint) : StaticArray(Point, 16)
      multiples = StaticArray(Point, 16).new(Point.from_affine(point))
      2.upto(16) do |multiple|
        multiples[multiple - 1] = multiple.even? ? multiples[multiple // 2 - 1].double : multiples[multiple - 2].add_affine(point, 0_u64)
      end
      multiples
    end

    # Returns whether the public *point* has Z = 1, so that its X and Y are
    # its affine coordinates. Variable time: for public points only.
    def self.public_point_has_unit_z?(point : Point) : Bool
      point.z == Field.set_one
    end

    # Returns entry *index* of the 16 points at *multiples*, reading all 16:
    # on the vector registers on AArch64, and on x86-64 with AVX2.
    @[AlwaysInline]
    def self.select_multiple(multiples : Pointer(Point), index : UInt64) : Point
      {% if flag?(:aarch64) && !flag?(:beryl_portable_curves) %}
        selected = uninitialized Point
        ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.select_entry_vector_statement({{ bytesize // 8 * 3 }}, 16, 0,
          pointerof(selected), multiples, index)
        selected
      {% elsif flag?(:x86_64) && !flag?(:beryl_portable_curves) %}
        return select_multiple_portable(multiples, index) unless ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_AVX2

        selected = uninitialized Point
        ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.select_entry_avx2_statement({{ bytesize // 8 * 3 }}, 16,
          pointerof(selected), multiples, index)
        selected
      {% else %}
        select_multiple_portable(multiples, index)
      {% end %}
    end

    # `select_multiple` by masks on the general registers.
    @[AlwaysInline]
    def self.select_multiple_portable(multiples : Pointer(Point), index : UInt64) : Point
      selected = Point.neutral
      16.times do |candidate|
        selected = selected.replace_if(ConstantTimeSelection.equal_bit(candidate.to_u64, index), multiples[candidate])
      end
      selected
    end

    # Returns entry *index* of the 16 affine points at *table*, reading all
    # 16; an index past the table gives (0, 0).
    @[AlwaysInline]
    def self.select_affine(table : Pointer(AffinePoint), index : UInt64) : AffinePoint
      {% if flag?(:aarch64) && !flag?(:beryl_portable_curves) %}
        selected = uninitialized AffinePoint
        ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.select_entry_vector_statement({{ bytesize // 8 * 2 }}, 16, 0,
          pointerof(selected), table, index)
        selected
      {% elsif flag?(:x86_64) && !flag?(:beryl_portable_curves) %}
        return select_affine_portable(table, index) unless ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_AVX2

        selected = uninitialized AffinePoint
        ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.select_entry_avx2_statement({{ bytesize // 8 * 2 }}, 16,
          pointerof(selected), table, index)
        selected
      {% else %}
        select_affine_portable(table, index)
      {% end %}
    end

    # `select_affine` by masks on the general registers.
    @[AlwaysInline]
    def self.select_affine_portable(table : Pointer(AffinePoint), index : UInt64) : AffinePoint
      selected_x = Limbs.new(0_u64)
      selected_y = Limbs.new(0_u64)
      16.times do |candidate|
        is_candidate = ConstantTimeSelection.equal_bit(candidate.to_u64, index)
        entry = table[candidate]
        selected_x = Field.selectznz(is_candidate, selected_x, entry.x)
        selected_y = Field.selectznz(is_candidate, selected_y, entry.y)
      end
      AffinePoint.new(selected_x, selected_y)
    end

    # Returns [scalar]point for a big-endian *scalar* of BYTESIZE bytes
    # below the group order n, in constant time, with *multiples* =
    # `multiples_of(point)`. The scalar is written in signed 5-bit windows
    # (Booth's recoding, as OpenSSL's `ecp_nistz256` does); from the most
    # significant window down, five doublings and then the addition of
    # [d]P, picked by reading all 16 multiples and negated by mask when
    # d < 0. Before window i is added the sum is [32·H]P, where
    # 32·H + d_i = H_i, the value of the digits from i up, which is
    # floor(scalar / 32^i) or one more, so 0 <= H_i < n. When H = 0 the
    # sum is infinity (handled by mask); otherwise 32·H >= 32 > |d_i| and
    # 32·H - d_i = H_i - 2·d_i lies strictly between 0 and n, so the two
    # operands are never equal.
    #
    # No step computes on infinity. While H = 0 the sum is marked by
    # *is_infinity* and holds a stand-in that starts at [32]P and is doubled
    # with the real sum, five times a window, so it is [2^e]P with e from 5
    # to 5 + 5·(windows - 1); its sums are computed and dropped by mask.
    # [2^e]P is never ±[d]P for d from 1 to 16: 2^e mod n is not ±d for any
    # of those e, which a spec checks for both curves. The stand-in changes
    # every window, because the same operands window after window (a
    # stand-in chosen afresh each time) still ran faster on AMD EPYC 9V74
    # for the key 1. A digit d = 0 reads [j]P, j = 1 + (i mod 16), a
    # different multiple from one window to the next, and drops the sum:
    # then H_i = 32·H with H >= 1, so 32·H - j lies strictly between 0 and
    # n, and [32·H]P is not [j]P; it is -[j]P only if H_i = n - j, a sum
    # that is dropped all the same. The top window starts the sum directly:
    # doubling infinity five times and adding [d]P to it would give [d]P all
    # the same.
    def self.multiply_constant_time(scalar : Bytes, multiples : StaticArray(Point, 16)) : Point
      multiples_pointer = pointerof(multiples).as(Point*)
      result, is_infinity = signed_multiple(scalar, GENERATOR_WINDOW_COUNT - 1, multiples_pointer)
      result = result.replace_if(is_infinity, multiples[15].double)
      {% if flag?(:x86_64) && !flag?(:beryl_portable_curves) && bytesize == 32 %}
        # P-256 on x86-64: each window in assembly statements on points
        # only the assembly reads until the end, so compiled code copies
        # nothing between steps: five doublings, each from one of two points
        # into the other, then one statement for the negation of the picked
        # multiple, the addition and both replacements, with the masks of
        # `signed_multiple` and `replace_if` in words 72 to 74 of the
        # scratch space (76 to 79 stay zero). The doublings run through
        # `double_into`, one copy of a doubling's code called five times: a
        # doubling is about 1,250 instructions, and five copies in the loop
        # (the compiler unrolls `5.times`) are more code than the
        # processor's decoded-instruction cache holds.
        state = result
        other_state = result
        current = pointerof(state)
        spare = pointerof(other_state)
        scratch = StaticArray(UInt64, 80).new(0_u64)
        (GENERATOR_WINDOW_COUNT - 2).downto(0) do |window_index|
          digit, is_negative = booth_digit(scalar, window_index)
          is_zero = ConstantTimeSelection.equal_bit(digit, 0_u64)
          stand_in_index = (window_index & 15).to_u64
          selected = select_multiple(multiples_pointer, (digit &- 1_u64) &+ (ConstantTimeSelection.mask_of(is_zero) & (stand_in_index &+ 1_u64)))
          scratch[72] = ConstantTimeSelection.mask_of(is_negative)
          scratch[73] = ConstantTimeSelection.mask_of(is_infinity)
          scratch[74] = ConstantTimeSelection.mask_of(is_zero)
          if ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
            5.times do
              double_into(pointerof(scratch), spare, current, true)
              current, spare = spare, current
            end
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(true,
              pointerof(scratch), current, 0, other: pointerof(selected), masks: true)
          else
            5.times do
              double_into(pointerof(scratch), spare, current, false)
              current, spare = spare, current
            end
            ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(false,
              pointerof(scratch), current, 0, other: pointerof(selected), masks: true)
          end
          is_infinity &= is_zero
        end
        SecretWiping.wipe(scratch.to_slice)
        return current.value.replace_if(is_infinity, Point.neutral)
      {% end %}
      (GENERATOR_WINDOW_COUNT - 2).downto(0) do |window_index|
        result = result.double_five_times
        selected, is_zero = signed_multiple(scalar, window_index, multiples_pointer)
        sum = result.add_unchecked(selected)
        sum = sum.replace_if(is_infinity, selected)
        result = sum.replace_if(is_zero, result)
        is_infinity &= is_zero
      end
      result.replace_if(is_infinity, Point.neutral)
    end

    {% if flag?(:x86_64) && !flag?(:beryl_portable_curves) && bytesize == 32 %}
      # P-256 on x86-64: doubles the point at *source* into *destination*
      # in one assembly statement (`mulx` when *wide*), with the scratch
      # space of `multiply_constant_time`. Never inlined, so that the
      # window loop runs one copy of the doubling's code.
      @[NoInline]
      def self.double_into(scratch : StaticArray(UInt64, 80)*, destination : Point*, source : Point*, wide : Bool) : Nil
        if wide
          ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(true, scratch, destination, 1, input: source)
        else
          ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_point_statement(false, scratch, destination, 1, input: source)
        end
      end
    {% end %}

    # Returns [d]P for the signed digit d of *scalar* at *window_index*,
    # from the 16 points at *multiples* (the multiple picked by reading all
    # 16, negated by mask when d < 0), and 1 when d = 0, else 0. For d = 0
    # the point is [1 + (window_index mod 16)]P, a real point for the caller
    # to compute on and drop.
    @[AlwaysInline]
    def self.signed_multiple(scalar : Bytes, window_index : Int32, multiples : Point*) : {Point, UInt64}
      digit, is_negative = booth_digit(scalar, window_index)
      is_zero = ConstantTimeSelection.equal_bit(digit, 0_u64)
      stand_in_index = (window_index & 15).to_u64
      selected = select_multiple(multiples, (digit &- 1_u64) &+ (ConstantTimeSelection.mask_of(is_zero) & (stand_in_index &+ 1_u64)))
      {Point.new(selected.x, Field.selectznz(is_negative, selected.y, Field.opp(selected.y)), selected.z), is_zero}
    end

    # Returns the magnitude (0 to 16) and the sign (1 when negative) of the
    # signed 5-bit digit of *scalar* at window *window_index*, from bits
    # 5i - 1 to 5i + 4, in constant time (OpenSSL's `_booth_recode_w5`).
    @[AlwaysInline]
    def self.booth_digit(scalar : Bytes, window_index : Int32) : {UInt64, UInt64}
      window = scalar_bits(scalar, window_index * 5 - 1)
      is_negative = window >> 5
      complement = 63_u64 &- window
      magnitude = (complement & (0_u64 &- is_negative)) | (window & (is_negative &- 1_u64))
      {(magnitude >> 1) &+ (magnitude & 1_u64), is_negative}
    end

    # Returns the 6 bits of the big-endian *scalar* from bit *low_bit* up
    # (bits below 0 and above the top read as 0). The positions are public.
    @[AlwaysInline]
    def self.scalar_bits(scalar : Bytes, low_bit : Int32) : UInt64
      bits = 0_u64
      6.times do |offset|
        position = low_bit + offset
        if 0 <= position < BYTESIZE * 8
          bits |= ((scalar.unsafe_fetch(BYTESIZE - 1 - (position >> 3)).to_u64 >> (position & 7)) & 1_u64) << offset
        end
      end
      bits
    end

    # Returns [scalar]G for a big-endian *scalar* of BYTESIZE bytes below
    # the group order n, in constant time, with no doubling and no zero
    # digit. The scalar is first made odd: an even k becomes n - k, and the
    # result is negated by mask at the end. The odd value m is written in
    # signed 5-bit windows whose digits are all odd, from -31 to 31
    # (`odd_digit`), so every window adds a point: [|d_i|·32^i]G, picked
    # from the precomputed table by reading all 16 entries, negated by mask
    # when d_i < 0, and added in affine form. No sum is dropped and no
    # operand stays the same from one window to the next.
    #
    # The two operands of an addition are never equal or opposite below the
    # top window: the sum so far is [S]G with S odd and |S| <= 31·(32^i -
    # 1)/31 < 32^i <= |d_i|·32^i, and |S ± d_i·32^i| < 32^(i + 1) <= n. At
    # the top window that bound passes n, so that one addition also computes
    # the doubling and keeps it by mask when the operands are equal; when
    # they are opposite (m = n, the scalar 0) its Z is 0, which is the
    # neutral element.
    #
    # Odd digits replaced the zero digit of Booth's recoding, which added
    # nothing: for a scalar such as 1 (51 zero digits of 52) the sum then
    # stayed the same point window after window, and on AMD EPYC 7763
    # (Zen 3) runners that ran measurably faster than a random scalar,
    # though no branch or address depended on it (docs/crypto/public-key.md,
    # "Timing on x86-64").
    def self.multiply_generator(scalar : Bytes) : Point
      list_of_tables = generator_window_tables
      odd_scalar = StaticArray(UInt8, BYTESIZE).new(0_u8)
      is_even = odd_scalar_of(scalar, odd_scalar.to_slice)
      digit_index, is_negative = odd_digit(odd_scalar.to_slice, 0)
      entry = select_affine(list_of_tables.to_unsafe.as(AffinePoint*), digit_index)
      result = Point.new(entry.x, Field.selectznz(is_negative, entry.y, Field.opp(entry.y)), Field.set_one)
      (1...GENERATOR_WINDOW_COUNT).each do |window_index|
        digit_index, is_negative = odd_digit(odd_scalar.to_slice, window_index)
        entry = select_affine((list_of_tables.to_unsafe + window_index).as(AffinePoint*), digit_index)
        entry = AffinePoint.new(entry.x, Field.selectznz(is_negative, entry.y, Field.opp(entry.y)))
        result = if window_index == GENERATOR_WINDOW_COUNT - 1
                   result.add_affine_or_double_unchecked(entry)
                 else
                   result.add_affine_unchecked(entry)
                 end
      end
      SecretWiping.wipe(odd_scalar.to_slice)
      result = Point.new(result.x, Field.selectznz(is_even, result.y, Field.opp(result.y)), result.z)
      result.replace_if(neutral_bit(result), Point.neutral)
    end

    # Writes into *odd_scalar* the big-endian *scalar* when it is odd and
    # n - *scalar* when it is even (n is odd, so either way the value is
    # odd), and returns 1 when *scalar* was even, else 0. In constant time:
    # the subtraction is always computed and kept by mask.
    @[AlwaysInline]
    def self.odd_scalar_of(scalar : Bytes, odd_scalar : Bytes) : UInt64
      is_even = (scalar.unsafe_fetch(BYTESIZE - 1).to_u64 & 1_u64) ^ 1_u64
      mask = ConstantTimeSelection.mask_of(is_even).to_u8!
      borrow = 0_u32
      (BYTESIZE - 1).downto(0) do |index|
        difference = GROUP_ORDER.unsafe_fetch(index).to_u32 &- scalar.unsafe_fetch(index).to_u32 &- borrow
        borrow = (difference >> 8) & 1_u32
        odd_scalar[index] = (difference.to_u8! & mask) | (scalar.unsafe_fetch(index) & ~mask)
      end
      is_even
    end

    # Returns the table index (0 to 15) and the sign (1 when negative) of
    # the odd signed digit of the odd big-endian *odd_scalar* at window
    # *window_index*, in constant time. Writing m_i = (m >> 5i) | 1, digit
    # d_i = (m_i mod 64) - 32 for every window but the top one, and the top
    # digit is m_i itself, below 32 for both curves: an odd number from -31
    # to 31 each time, |d_i| = 2·index + 1. The digits sum to m, because
    # m_(i + 1) = (m_i - d_i) / 32 (the regular recoding of Joye and
    # Tunstall).
    @[AlwaysInline]
    def self.odd_digit(odd_scalar : Bytes, window_index : Int32) : {UInt64, UInt64}
      window = scalar_bits(odd_scalar, window_index * 5) | 1_u64
      return {window >> 1, 0_u64} if window_index == GENERATOR_WINDOW_COUNT - 1
      is_negative = ((window >> 5) & 1_u64) ^ 1_u64
      mask = ConstantTimeSelection.mask_of(is_negative)
      magnitude = ((32_u64 &- window) & mask) | ((window &- 32_u64) & ~mask)
      {magnitude >> 1, is_negative}
    end

    # The width-*width* signed digits of a public big-endian *scalar*
    # (non-adjacent form): every nonzero digit is odd and below
    # 2^(width - 1) in size, and at most one of any *width* digits in a row
    # is nonzero. Digit i weighs 2^i.
    def self.signed_digits(scalar : Bytes, width : Int32) : Array(Int32)
      words = Array(UInt64).new(LIMB_COUNT + 1, 0_u64)
      BYTESIZE.times do |offset|
        words[offset >> 3] |= scalar[BYTESIZE - 1 - offset].to_u64 << ((offset & 7) * 8)
      end
      list_of_digits = Array(Int32).new(BYTESIZE * 8 + 1, 0)
      window_mask = (1_u64 << width) - 1
      position = 0
      until words.all?(&.zero?)
        if words[0].odd?
          digit = (words[0] & window_mask).to_i32
          digit -= 1 << width if digit >= 1 << (width - 1)
          if digit > 0
            borrow = digit.to_u64
            words.size.times do |index|
              before = words[index]
              words[index] = before &- borrow
              borrow = before < borrow ? 1_u64 : 0_u64
            end
          else
            carry = (-digit).to_u64
            words.size.times do |index|
              words[index] = words[index] &+ carry
              carry = words[index] < carry ? 1_u64 : 0_u64
            end
          end
          list_of_digits[position] = digit
        end
        (words.size - 1).times { |index| words[index] = (words[index] >> 1) | (words[index + 1] << 63) }
        words[words.size - 1] >>= 1
        position += 1
      end
      list_of_digits
    end

    # Returns [first_scalar]G + [second_scalar]point, in variable time, for
    # signature verification, where every input is public: both scalars in
    # signed digits (width 7 for G, from the precomputed odd multiples; width
    # 5 for the point), one shared run of doublings.
    def self.multiply_and_add_public(first_scalar : Bytes, point : Point, second_scalar : Bytes) : Point
      first_digits = signed_digits(first_scalar, 7)
      second_digits = signed_digits(second_scalar, 5)
      generator_multiples = generator_odd_multiples
      point_multiples = Array(Point).new(8, point)
      twice_point = point.double
      1.upto(7) { |index| point_multiples[index] = point_multiples[index - 1].add_public(twice_point) }

      result = Point.neutral
      (first_digits.size - 1).downto(0) do |position|
        result = result.double unless neutral_bit(result) == 1
        first_digit = first_digits[position]
        if first_digit != 0
          multiple = generator_multiples[first_digit.abs >> 1]
          multiple = AffinePoint.new(multiple.x, Field.opp(multiple.y)) if first_digit < 0
          result = result.add_affine_public(multiple)
        end
        second_digit = second_digits[position]
        if second_digit != 0
          multiple = point_multiples[second_digit.abs >> 1]
          multiple = multiple.negate if second_digit < 0
          result = result.add_public(multiple)
        end
      end
      result
    end

    # Decodes a SEC 1 §2.3.4 point: 0x04 || X || Y or 0x02/0x03 || X.
    # Returns nil for any other form, a coordinate not below p, a point off
    # the curve, or the point at infinity. The input is public.
    def self.decode_point(encoded : Bytes) : Point?
      return nil if encoded.empty?

      form = encoded[0]
      return decode_uncompressed_point(encoded) if form == 0x04_u8 && encoded.size == 1 + 2 * BYTESIZE
      return decode_compressed_point(encoded) if (form == 0x02_u8 || form == 0x03_u8) && encoded.size == 1 + BYTESIZE

      nil
    end

    private def self.decode_uncompressed_point(encoded : Bytes) : Point?
      encoded_x = encoded[1, BYTESIZE]
      encoded_y = encoded[1 + BYTESIZE, BYTESIZE]
      return nil unless below_bit(encoded_x, FIELD_PRIME) == 1 && below_bit(encoded_y, FIELD_PRIME) == 1

      x = field_element_from_big_endian(encoded_x)
      y = field_element_from_big_endian(encoded_y)
      return nil unless field_equal_bit(Field.square(y), curve_right_side(x)) == 1

      Point.new(x, y, Field.set_one)
    end

    private def self.decode_compressed_point(encoded : Bytes) : Point?
      encoded_x = encoded[1, BYTESIZE]
      return nil unless below_bit(encoded_x, FIELD_PRIME) == 1

      x = field_element_from_big_endian(encoded_x)
      right_side = curve_right_side(x)
      y = field_power(right_side, square_root_exponent)
      return nil unless field_equal_bit(Field.square(y), right_side) == 1

      y_is_odd = field_element_to_big_endian(y)[BYTESIZE - 1] & 1
      y = Field.opp(y) unless y_is_odd == (encoded[0] & 1)
      Point.new(x, y, Field.set_one)
    end

    # Returns the SEC 1 uncompressed encoding 0x04 || X || Y.
    def self.encode_uncompressed(point : Point) : Bytes
      x, y = to_affine(point)
      encoded = Bytes.new(1 + 2 * BYTESIZE)
      encoded[0] = 0x04_u8
      field_element_to_big_endian(x).copy_to(encoded[1, BYTESIZE])
      field_element_to_big_endian(y).copy_to(encoded[1 + BYTESIZE, BYTESIZE])
      encoded
    end

    # Returns the SEC 1 compressed encoding 0x02/0x03 || X.
    def self.encode_compressed(point : Point) : Bytes
      x, y = to_affine(point)
      encoded = Bytes.new(1 + BYTESIZE)
      encoded[0] = 0x02_u8 | (field_element_to_big_endian(y)[BYTESIZE - 1] & 1)
      field_element_to_big_endian(x).copy_to(encoded[1, BYTESIZE])
      encoded
    end

    # The x coordinate of *point* reduced modulo n, outside the Montgomery
    # domain (the r of ECDSA).
    def self.x_coordinate_modulo_order(point : Point) : Limbs
      reduce_once_modulo_order(field_element_to_big_endian(to_affine_x(point)))
    end

    # Returns whether the x coordinate of the public *point* (not at
    # infinity), reduced modulo n, equals the big-endian *encoded_r*
    # (below n), without an inversion: x = X/Z^2 is r or r + n (the only
    # values below p that reduce to r, the second only when r + n < p),
    # so it checks r·Z^2 = X and (r + n)·Z^2 = X instead. Variable time;
    # verification's inputs are public.
    def self.x_coordinate_matches_public?(point : Point, encoded_r : Bytes) : Bool
      z_squared = Field.square(point.z)
      return true if Field.mul(field_element_from_big_endian(encoded_r), z_squared) == point.x

      r_plus_order = Bytes.new(BYTESIZE)
      carry = 0
      (BYTESIZE - 1).downto(0) do |index|
        sum = encoded_r[index].to_i32 + GROUP_ORDER[index].to_i32 + carry
        r_plus_order[index] = (sum & 0xff).to_u8
        carry = sum >> 8
      end
      return false unless carry == 0 && below_bit(r_plus_order, FIELD_PRIME) == 1

      Field.mul(field_element_from_big_endian(r_plus_order), z_squared) == point.x
    end

    # Returns the leftmost bits of a digest as an integer below
    # 2^(8 * BYTESIZE) (FIPS 186-5 §6.4.1 step 4, RFC 6979 bits2int), as
    # BYTESIZE big-endian bytes. The orders of both curves fill whole bytes.
    def self.digest_to_integer(digest : Bytes) : Bytes
      return digest[0, BYTESIZE].dup unless digest.size < BYTESIZE

      integer = Bytes.new(BYTESIZE)
      digest.copy_to(integer[BYTESIZE - digest.size, digest.size])
      integer
    end
  end
end
