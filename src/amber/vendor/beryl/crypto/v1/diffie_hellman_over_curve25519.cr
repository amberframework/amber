require "random/secure"
require "../error"
require "../secret_wiping"
require "../field_arithmetic"
require "../constant_time_selection"
require "../declassification"
require "../data_independent_timing"
require "./curve25519_field_element"
require "./edwards25519_group"

module Amber::Beryl::Crypto::V1
  # X25519 key agreement (RFC 7748 §5 and §6.1).
  #
  # ```
  # mine = Amber::Beryl::Crypto::V1::X25519::PrivateKey.generate
  # send(mine.public_key.to_slice) # 32 bytes
  # shared = mine.shared_secret(X25519::PublicKey.new(received_bytes))
  # # => 32 bytes, or nil when the peer sent a point of small order
  # ```
  #
  # The scalar multiplication is a Montgomery ladder of 255 steps whose
  # conditional swap is a mask, on field arithmetic generated from
  # fiat-crypto. Its running time does not depend on the private key.
  module DiffieHellmanOverCurve25519
    KEY_BYTESIZE = 32

    private alias Field = Amber::Beryl::Crypto::FieldArithmetic::Curve25519Field

    # The u-coordinate of the base point, 9 (RFC 7748 §4.1).
    BASE_POINT_U = Bytes.new(KEY_BYTESIZE) { |index| index == 0 ? 9_u8 : 0_u8 }

    # A public key: 32 bytes, the u-coordinate of a point. Every 32-byte
    # value is accepted, as RFC 7748 §5 requires; a point of small order
    # shows up as an all-zero shared secret, which `shared_secret` refuses.
    struct PublicKey
      getter bytes : StaticArray(UInt8, 32)

      def initialize(encoded : Bytes)
        unless encoded.size == KEY_BYTESIZE
          raise KeySizeMismatch.new("an X25519 public key is #{KEY_BYTESIZE} bytes, not #{encoded.size}")
        end
        @bytes = StaticArray(UInt8, 32).new { |index| encoded[index] }
      end

      def to_slice : Bytes
        Bytes.new(KEY_BYTESIZE) { |index| @bytes[index] }
      end

      def ==(other : PublicKey) : Bool
        @bytes == other.bytes
      end
    end

    # A private key: 32 secret bytes, clamped as RFC 7748 §5 describes each
    # time they are used.
    class PrivateKey
      @secret : Bytes

      # Returns a new private key from `Random::Secure`.
      def self.generate : self
        secret = Bytes.new(KEY_BYTESIZE)
        Random::Secure.random_bytes(secret)
        key = new(secret)
        SecretWiping.wipe(secret)
        key
      end

      # Keeps a copy of *secret* (32 bytes).
      def initialize(secret : Bytes)
        unless secret.size == KEY_BYTESIZE
          raise KeySizeMismatch.new("an X25519 private key is #{KEY_BYTESIZE} bytes, not #{secret.size}")
        end
        @secret = secret.dup
      end

      # Returns the matching public key, X25519(secret, 9).
      def public_key : PublicKey
        PublicKey.new(DiffieHellmanOverCurve25519.multiply_base_point(@secret))
      end

      # Returns the 32-byte shared secret with *peer*, or `nil` when it is
      # all zero, which happens only when the peer sent a point of small
      # order (RFC 7748 §6.1; RFC 9846 §7.4.2 requires the check).
      def shared_secret(peer : PublicKey) : Bytes?
        shared = DiffieHellmanOverCurve25519.scalar_multiply(@secret, peer.to_slice)
        is_all_zero = ConstantTimeSelection.all_zero_bit(shared)
        return shared unless Declassification.reveal(is_all_zero == 1_u64)

        SecretWiping.wipe(shared)
        nil
      end

      # Returns a copy of the private key's 32 bytes.
      def to_slice : Bytes
        @secret.dup
      end

      def finalize
        SecretWiping.wipe(@secret)
      end
    end

    # Returns X25519(*scalar*, *u_coordinate*) (RFC 7748 §5): both 32 bytes.
    def self.scalar_multiply(scalar : Bytes, u_coordinate : Bytes) : Bytes
      DataIndependentTiming.run do
        clamped = StaticArray(UInt8, 32).new { |index| scalar.unsafe_fetch(index) }
        clamped[0] &= 248_u8
        clamped[31] &= 127_u8
        clamped[31] |= 64_u8
        u_bytes = StaticArray(UInt8, 32).new { |index| u_coordinate.unsafe_fetch(index) }
        u_bytes[31] &= 0x7f_u8

        result = ladder(clamped, Field.from_bytes(u_bytes), random_coordinate_factor)
        SecretWiping.wipe(clamped.to_slice)
        Bytes.new(KEY_BYTESIZE) { |index| result[index] }
      end
    end

    # Returns X25519(*scalar*, 9), the public key of *scalar*, the same
    # bytes `scalar_multiply(scalar, BASE_POINT_U)` gives, in about a third
    # of the time: the base point u = 9 is the image of the edwards25519
    # base point B under the birational map u = (1 + y) / (1 - y) (RFC 7748
    # §4.1), so the key is [k]B, computed with the precomputed tables of
    # `Edwards25519Group.multiply_base` and mapped across. Constant time.
    def self.multiply_base_point(scalar : Bytes) : Bytes
      DataIndependentTiming.run do
        clamped = Bytes.new(KEY_BYTESIZE) { |index| scalar.unsafe_fetch(index) }
        clamped[0] &= 248_u8
        clamped[31] &= 127_u8
        clamped[31] |= 64_u8
        point = Edwards25519Group.multiply_base(clamped)
        SecretWiping.wipe(clamped)
        # y = Y / Z, so (1 + y) / (1 - y) = (Z + Y) / (Z - Y).
        u = (point.z + point.y) * (point.z - point.y).invert
        encoded = u.to_bytes
        Bytes.new(KEY_BYTESIZE) { |index| encoded[index] }
      end
    end

    # A random nonzero field element for `ladder`'s projective coordinates:
    # 255 random bits with the lowest set, so it is odd and below 2^255; it
    # is 0 modulo p only if it equals p, a chance of 2^-254.
    private def self.random_coordinate_factor : Field::Limbs
      random_bytes = StaticArray(UInt8, 32).new(0_u8)
      Random::Secure.random_bytes(random_bytes.to_slice)
      random_bytes[0] |= 1_u8
      random_bytes[31] &= 0x7f_u8
      factor = Field.from_bytes(random_bytes)
      SecretWiping.wipe(random_bytes.to_slice)
      factor
    end

    # The Montgomery ladder of RFC 7748 §5. Field bounds: sums and
    # differences of tight elements are loose, `carry_mul`, `carry_square`
    # and `carry_scmul_121666` take loose elements and return tight ones.
    # `a24` enters as z_2 = E * (BB + 121666 * E), which equals RFC 7748's
    # E * (AA + 121665 * E) because AA = BB + E.
    #
    # The ladder starts from (x_2 : z_2) = (λ : 0) and (x_3 : z_3) =
    # (λ·u : λ) for a random nonzero *factor* λ rather than (1 : 0) and
    # (u : 1): the same points, so the same result, but every intermediate
    # value is new on each call. On AMD EPYC 9V74 (Zen 4) runners a fixed
    # scalar (all zero, all ones, or one random scalar) took a measurably
    # different time from fresh random scalars (|t| up to 17 at 1,000,000
    # measurements per class), though no branch or address depends on the
    # scalar; with the random start, every case stayed under 2.6
    # (docs/crypto/public-key.md, "Timing on x86-64").
    @[NoInline]
    private def self.ladder(clamped : StaticArray(UInt8, 32), x1 : Field::Limbs, factor : Field::Limbs) : StaticArray(UInt8, 32)
      x2 = factor
      z2 = Field::Limbs.new(0_u64)
      x3 = Field.carry_mul(x1, factor)
      z3 = factor
      swap = 0_u64

      254.downto(0) do |bit_index|
        bit = (clamped[bit_index >> 3].to_u64 >> (bit_index & 7)) & 1_u64
        swap ^= bit
        x2, x3 = Field.selectznz(swap, x2, x3), Field.selectznz(swap, x3, x2)
        z2, z3 = Field.selectznz(swap, z2, z3), Field.selectznz(swap, z3, z2)
        swap = bit

        a = Field.add(x2, z2)
        aa = Field.carry_square(a)
        b = Field.sub(x2, z2)
        bb = Field.carry_square(b)
        e = Field.sub(aa, bb)
        c = Field.add(x3, z3)
        d = Field.sub(x3, z3)
        da = Field.carry_mul(d, a)
        cb = Field.carry_mul(c, b)
        x3 = Field.carry_square(Field.add(da, cb))
        z3 = Field.carry_mul(x1, Field.carry_square(Field.sub(da, cb)))
        x2 = Field.carry_mul(aa, bb)
        z2 = Field.carry_mul(e, Field.add(bb, Field.carry_scmul_121666(e)))
      end
      x2 = Field.selectznz(swap, x2, x3)
      z2 = Field.selectznz(swap, z2, z3)

      affine_u = Curve25519FieldElement.new(x2) * Curve25519FieldElement.new(z2).invert
      affine_u.to_bytes
    end
  end

  alias X25519 = DiffieHellmanOverCurve25519
end
