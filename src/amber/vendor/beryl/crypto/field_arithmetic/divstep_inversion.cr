module Amber::Beryl::Crypto::FieldArithmetic
  # :nodoc:
  #
  # Inversion modulo an odd modulus below 2^256 in constant time, by the
  # "divsteps" of Bernstein and Yang ("Fast constant-time gcd computation
  # and modular inversion", 2019), as libsecp256k1 writes them
  # (`src/modinv64_impl.h`, `secp256k1_modinv64`, the constant-time
  # variant): 10 rounds of 59 divsteps, 590 in all, which is enough for any
  # pair of 256-bit inputs (libsecp256k1's `doc/safegcd_implementation.md`
  # gives the bound). Each round works on the low 64 bits alone to find a
  # 2×2 transition matrix, then applies it to the full numbers f, g (the
  # gcd state) and d, e (the Bézout coefficients, kept modulo the modulus).
  #
  # It replaces exponentiation by modulus - 2 (Fermat) where the curves
  # invert: about 255 squarings and 40 multiplications become 590 steps of
  # a few masked additions each, and 20 small matrix products.
  #
  # Numbers are held as five signed 62-bit limbs ("signed62"), so a limb
  # times a matrix entry, plus another, fits in a 128-bit integer.
  #
  # Constant time: every round runs every step; the one decision of a
  # divstep (whether delta is positive and g odd) is a mask, as are the sign
  # corrections, and nothing indexes memory or branches on a value.
  # Additions wrap (`&+`), so nothing raises on overflow either.
  module DivstepInversion
    alias Signed62 = StaticArray(Int64, 5)
    alias Words = StaticArray(UInt64, 4)

    LOW_62_BITS = UInt64::MAX >> 2

    # An odd modulus below 2^256 in signed62 form, with its inverse
    # modulo 2^62.
    record Modulus, limbs : Signed62, inverse_modulo_2_to_62 : UInt64

    # Returns the `Modulus` for the little-endian *words* (odd, public).
    def self.modulus_of(words : Words) : Modulus
      inverse = words[0]
      5.times { inverse = inverse &* (2_u64 &- words[0] &* inverse) }
      Modulus.new(to_signed62(words), inverse & LOW_62_BITS)
    end

    # Returns *value*^-1 mod *modulus* for a little-endian *value* below the
    # modulus, and 0 for 0.
    def self.invert(value : Words, modulus : Modulus) : Words
      d = Signed62.new(0_i64)
      e = Signed62.new(0_i64)
      e[0] = 1_i64
      f = modulus.limbs
      g = to_signed62(value)
      # zeta = -(delta + 1/2), with delta starting at 1/2.
      zeta = -1_i64
      10.times do
        zeta, u, v, q, r = divsteps_59(zeta, f[0].to_u64!, g[0].to_u64!)
        d, e = update_coefficients(d, e, u, v, q, r, modulus)
        f, g = update_gcd_state(f, g, u, v, q, r)
      end
      # g is now 0 and f is ±1 (the gcd), so d·value = ±1: d is the inverse
      # up to the sign of f.
      to_words(normalize(d, f[4], modulus))
    end

    # Returns *value* as five signed 62-bit limbs (all nonnegative).
    @[AlwaysInline]
    def self.to_signed62(value : Words) : Signed62
      Signed62[
        (value[0] & LOW_62_BITS).to_i64!,
        (((value[0] >> 62) | (value[1] << 2)) & LOW_62_BITS).to_i64!,
        (((value[1] >> 60) | (value[2] << 4)) & LOW_62_BITS).to_i64!,
        (((value[2] >> 58) | (value[3] << 6)) & LOW_62_BITS).to_i64!,
        (value[3] >> 56).to_i64!,
      ]
    end

    # Returns the little-endian words of normalized limbs (each below 2^62,
    # the value below 2^256).
    @[AlwaysInline]
    def self.to_words(limbs : Signed62) : Words
      l0, l1, l2, l3, l4 = limbs[0].to_u64!, limbs[1].to_u64!, limbs[2].to_u64!, limbs[3].to_u64!, limbs[4].to_u64!
      Words[l0 | (l1 << 62), (l1 >> 2) | (l2 << 60), (l2 >> 4) | (l3 << 58), (l3 >> 6) | (l4 << 56)]
    end

    # Fifty-nine divsteps on the low bits *f0* and *g0* of f and g, from
    # *zeta*. Returns the new zeta and the transition matrix (u v; q r),
    # scaled by 2^62, such that 2^62·(f', g') = (u·f + v·g, q·f + r·g).
    # libsecp256k1's `secp256k1_modinv64_divsteps_59`.
    @[AlwaysInline]
    def self.divsteps_59(zeta : Int64, f0 : UInt64, g0 : UInt64) : {Int64, Int64, Int64, Int64, Int64}
      u = 8_u64
      v = 0_u64
      q = 0_u64
      r = 8_u64
      f = f0
      g = g0
      current_zeta = zeta.to_u64!
      59.times do
        # All ones when zeta < 0 (delta > 0), and when g is odd.
        is_delta_positive = barrier((current_zeta.to_i64! >> 63).to_u64!)
        is_g_odd = barrier(0_u64 &- (g & 1_u64))
        # When g is odd, add f to g (or -f when delta > 0), and likewise
        # the matrix rows.
        f_signed = (f ^ is_delta_positive) &- is_delta_positive
        u_signed = (u ^ is_delta_positive) &- is_delta_positive
        v_signed = (v ^ is_delta_positive) &- is_delta_positive
        g &+= f_signed & is_g_odd
        q &+= u_signed & is_g_odd
        r &+= v_signed & is_g_odd
        # When both, also swap: f takes the old g, and zeta changes sign.
        does_swap = is_delta_positive & is_g_odd
        current_zeta = (current_zeta ^ does_swap) &- 1_u64
        f &+= g & does_swap
        u &+= q & does_swap
        v &+= r & does_swap
        g >>= 1
        u <<= 1
        v <<= 1
      end
      {current_zeta.to_i64!, u.to_i64!, v.to_i64!, q.to_i64!, r.to_i64!}
    end

    # Returns (d', e') = (u·d + v·e, q·d + r·e) / 2^62 modulo the modulus,
    # with multiples of the modulus added so the division is exact and the
    # results stay in (-2·modulus, modulus). libsecp256k1's
    # `secp256k1_modinv64_update_de_62`.
    @[AlwaysInline]
    def self.update_coefficients(d : Signed62, e : Signed62, u : Int64, v : Int64, q : Int64, r : Int64,
                                 modulus : Modulus) : {Signed62, Signed62}
      modulus_limbs = modulus.limbs
      # Start the multiples of the modulus at u or q (when d < 0) plus v or
      # r (when e < 0), which keeps the results in range.
      d_sign = d[4] >> 63
      e_sign = e[4] >> 63
      multiple_d = (u & d_sign) &+ (v & e_sign)
      multiple_e = (q & d_sign) &+ (r & e_sign)
      sum_d = u.to_i128 &* d[0] &+ v.to_i128 &* e[0]
      sum_e = q.to_i128 &* d[0] &+ r.to_i128 &* e[0]
      # Choose the multiples so the low 62 bits of each sum come out zero.
      multiple_d &-= ((modulus.inverse_modulo_2_to_62 &* sum_d.to_u64! &+ multiple_d.to_u64!) & LOW_62_BITS).to_i64!
      multiple_e &-= ((modulus.inverse_modulo_2_to_62 &* sum_e.to_u64! &+ multiple_e.to_u64!) & LOW_62_BITS).to_i64!
      sum_d &+= modulus_limbs[0].to_i128 &* multiple_d
      sum_e &+= modulus_limbs[0].to_i128 &* multiple_e
      sum_d = sum_d.unsafe_shr(62)
      sum_e = sum_e.unsafe_shr(62)
      new_d = Signed62.new(0_i64)
      new_e = Signed62.new(0_i64)
      {% for limb in 1..4 %}
        sum_d &+= u.to_i128 &* d[{{ limb }}] &+ v.to_i128 &* e[{{ limb }}] &+ modulus_limbs[{{ limb }}].to_i128 &* multiple_d
        sum_e &+= q.to_i128 &* d[{{ limb }}] &+ r.to_i128 &* e[{{ limb }}] &+ modulus_limbs[{{ limb }}].to_i128 &* multiple_e
        new_d[{{ limb - 1 }}] = (sum_d.to_u64! & LOW_62_BITS).to_i64!
        new_e[{{ limb - 1 }}] = (sum_e.to_u64! & LOW_62_BITS).to_i64!
        sum_d = sum_d.unsafe_shr(62)
        sum_e = sum_e.unsafe_shr(62)
      {% end %}
      new_d[4] = sum_d.to_i64!
      new_e[4] = sum_e.to_i64!
      {new_d, new_e}
    end

    # Returns (f', g') = (u·f + v·g, q·f + r·g) / 2^62; the divsteps made
    # the low 62 bits zero. libsecp256k1's `secp256k1_modinv64_update_fg_62`.
    @[AlwaysInline]
    def self.update_gcd_state(f : Signed62, g : Signed62, u : Int64, v : Int64, q : Int64, r : Int64) : {Signed62, Signed62}
      sum_f = u.to_i128 &* f[0] &+ v.to_i128 &* g[0]
      sum_g = q.to_i128 &* f[0] &+ r.to_i128 &* g[0]
      sum_f = sum_f.unsafe_shr(62)
      sum_g = sum_g.unsafe_shr(62)
      new_f = Signed62.new(0_i64)
      new_g = Signed62.new(0_i64)
      {% for limb in 1..4 %}
        sum_f &+= u.to_i128 &* f[{{ limb }}] &+ v.to_i128 &* g[{{ limb }}]
        sum_g &+= q.to_i128 &* f[{{ limb }}] &+ r.to_i128 &* g[{{ limb }}]
        new_f[{{ limb - 1 }}] = (sum_f.to_u64! & LOW_62_BITS).to_i64!
        new_g[{{ limb - 1 }}] = (sum_g.to_u64! & LOW_62_BITS).to_i64!
        sum_f = sum_f.unsafe_shr(62)
        sum_g = sum_g.unsafe_shr(62)
      {% end %}
      new_f[4] = sum_f.to_i64!
      new_g[4] = sum_g.to_i64!
      {new_f, new_g}
    end

    # Brings *value*, in (-2·modulus, modulus), to [0, modulus), negated
    # when *sign* is negative. libsecp256k1's
    # `secp256k1_modinv64_normalize_62`.
    @[AlwaysInline]
    def self.normalize(value : Signed62, sign : Int64, modulus : Modulus) : Signed62
      modulus_limbs = modulus.limbs
      limbs = value
      add_modulus = barrier_signed(limbs[4] >> 63)
      5.times { |index| limbs[index] &+= modulus_limbs[index] & add_modulus }
      negate = barrier_signed(sign >> 63)
      5.times { |index| limbs[index] = (limbs[index] ^ negate) &- negate }
      limbs = propagate_carries(limbs)
      add_modulus = barrier_signed(limbs[4] >> 63)
      5.times { |index| limbs[index] &+= modulus_limbs[index] & add_modulus }
      propagate_carries(limbs)
    end

    @[AlwaysInline]
    private def self.propagate_carries(value : Signed62) : Signed62
      limbs = value
      4.times do |index|
        limbs[index + 1] &+= limbs[index] >> 62
        limbs[index] &= LOW_62_BITS.to_i64!
      end
      limbs
    end

    # Value barriers, as fiat-crypto's `value_barrier_u64`: the optimizer
    # cannot see through the empty assembly, so it cannot turn a mask back
    # into a branch.
    @[AlwaysInline]
    def self.barrier(value : UInt64) : UInt64
      barred = value
      asm("" : "=r"(barred) : "0"(value))
      barred
    end

    @[AlwaysInline]
    def self.barrier_signed(value : Int64) : Int64
      barrier(value.to_u64!).to_i64!
    end
  end
end
