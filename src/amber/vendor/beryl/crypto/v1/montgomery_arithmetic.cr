require "./montgomery_multiplication_in_assembly"
require "./montgomery_multiplication_with_two_carry_chains"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # Arithmetic modulo an odd number of up to 8,192 bits, in Montgomery form,
  # for RSA. The design follows BearSSL's `i31` and `i62` code
  # (`src/int/i31_montmul.c`, `i31_modpow2.c`, `i62_modpow2.c`,
  # `i31_decred.c`), written for 64-bit words: a number is a
  # `Slice(UInt64)` of little-endian words, every number modulo *m* has as
  # many words as *m*, and a word product is a `UInt128`.
  #
  # Every method here runs in time that depends only on the sizes of its
  # arguments, never on their values, except
  # `exponentiate_by_public_exponent`, whose exponent is public: it uses
  # wrapping operators on every value, selects with masks instead of
  # branches, reads every entry of a table and keeps the one it wants, and
  # never divides. Sizes (word counts, byte counts, bit counts of
  # exponents) are public.
  #
  # Montgomery form: for a modulus *m* of *n* words, R = 2^(64n), and the
  # Montgomery form of *x* is x·R mod m. `multiply` returns a·b/R mod m, so
  # it multiplies two numbers in Montgomery form and keeps the result in it.
  module MontgomeryArithmetic
    # Window of the constant-time exponentiation, in exponent bits: a table
    # of 2^WINDOW_BIT_COUNT powers is built and read once per window. Five
    # bits cost one multiplication per five squarings, and reading the 32
    # entries costs less than the multiplications a four-bit window adds
    # for exponents of 1,024 bits and more.
    WINDOW_BIT_COUNT  = 5
    TABLE_ENTRY_COUNT = 1 << WINDOW_BIT_COUNT

    # Returns *value* unchanged, through an empty piece of inline assembly
    # that keeps the optimizer from turning a mask computed from it back
    # into a branch.
    @[AlwaysInline]
    def self.barrier(value : UInt64) : UInt64
      asm("" : "=r"(value) : "0"(value))
      value
    end

    # Returns all ones when *bit* is 1, and zero when it is 0.
    @[AlwaysInline]
    def self.mask_of(bit : UInt64) : UInt64
      barrier(0_u64 &- bit)
    end

    # Returns 1 when *value* is zero, and 0 otherwise.
    @[AlwaysInline]
    def self.zero_bit_of(value : UInt64) : UInt64
      ((value | (0_u64 &- value)) >> 63) ^ 1_u64
    end

    # Returns the number of words that hold a number of *bytesize* bytes.
    def self.word_count_for(bytesize : Int32) : Int32
      (bytesize + 7) // 8
    end

    # Reads the big-endian *bytes* into *words*. Returns 1 when the value
    # fits in *words*, and 0 when a byte past what *words* holds is not
    # zero; the bytes that fit are read either way.
    def self.decode_big_endian(bytes : Bytes, words : Slice(UInt64)) : UInt64
      words.fill(0_u64)
      overflow = 0_u64
      capacity = words.size * 8
      bytes.size.times do |position_from_end|
        byte = bytes[bytes.size - 1 - position_from_end].to_u64
        if position_from_end < capacity
          words[position_from_end // 8] |= byte << (8 * (position_from_end % 8))
        else
          overflow |= byte
        end
      end
      zero_bit_of(overflow)
    end

    # Writes *words* into *bytes*, big-endian, filling all of *bytes*: the
    # high bytes are zero when *bytes* is longer than the number, and the
    # high words are cut off when it is shorter.
    def self.encode_big_endian(words : Slice(UInt64), bytes : Bytes) : Nil
      bytes.size.times do |position_from_end|
        word_index = position_from_end // 8
        byte = word_index < words.size ? (words[word_index] >> (8 * (position_from_end % 8))).to_u8! : 0_u8
        bytes[bytes.size - 1 - position_from_end] = byte
      end
    end

    # Returns the number of significant bits in *words*: the position of
    # its highest set bit plus one, or zero for zero. Every word is read.
    def self.bit_length(words : Slice(UInt64)) : UInt64
      result = 0_u64
      words.size.times do |index|
        word = words[index]
        word_bit_length = 64_u64 &- word.leading_zeros_count.to_u64
        is_nonzero = zero_bit_of(word) ^ 1_u64
        position = (index.to_u64 &* 64_u64) &+ word_bit_length
        result = (result & ~mask_of(is_nonzero)) | (position & mask_of(is_nonzero))
      end
      result
    end

    # Returns 1 when *first* is less than *second* (same size), else 0.
    def self.less_than_bit(first : Slice(UInt64), second : Slice(UInt64)) : UInt64
      borrow = 0_u64
      first.size.times do |index|
        difference = first[index].to_u128 &- second[index].to_u128 &- borrow.to_u128
        borrow = (difference >> 127).to_u64!
      end
      borrow
    end

    # Returns 1 when *first* equals *second* (same size), else 0.
    def self.equal_bit(first : Slice(UInt64), second : Slice(UInt64)) : UInt64
      accumulated = 0_u64
      first.size.times { |index| accumulated |= first[index] ^ second[index] }
      zero_bit_of(accumulated)
    end

    # Returns 1 when *words* is zero, else 0.
    def self.zero_bit_of(words : Slice(UInt64)) : UInt64
      accumulated = 0_u64
      words.size.times { |index| accumulated |= words[index] }
      zero_bit_of(accumulated)
    end

    # Returns -m^-1 mod 2^64 for the odd low word *low_word* of a modulus,
    # by Newton's iteration: each step doubles the number of correct low
    # bits, from 3 (any odd x is its own inverse mod 8) to 96.
    def self.negated_inverse_of_low_word(low_word : UInt64) : UInt64
      inverse = low_word
      5.times { inverse = inverse &* (2_u64 &- low_word &* inverse) }
      0_u64 &- inverse
    end

    # Sets *destination* to *source* when *bit* is 1, and leaves it when 0.
    def self.conditional_copy(destination : Slice(UInt64), source : Slice(UInt64), bit : UInt64) : Nil
      mask = mask_of(bit)
      destination_pointer = destination.to_unsafe
      source_pointer = source.to_unsafe
      destination.size.times do |index|
        destination_pointer[index] ^= (destination_pointer[index] ^ source_pointer[index]) & mask
      end
    end

    # Sets *result* to a·b/R mod *modulus*, with *negated_inverse* =
    # `negated_inverse_of_low_word(modulus[0])`. *b* must be below the
    # modulus; *a* may be any number of as many words (its product with *b*
    # still reduces to below the modulus). *result* may be *a* or *b*.
    # *scratch* holds at least `multiplication_scratch_word_count` words.
    def self.multiply(result : Slice(UInt64), a : Slice(UInt64), b : Slice(UInt64), modulus : Slice(UInt64),
                      negated_inverse : UInt64, scratch : Slice(UInt64)) : Nil
      result_pointer, a_pointer, b_pointer = result.to_unsafe, a.to_unsafe, b.to_unsafe
      modulus_pointer, accumulator = modulus.to_unsafe, scratch.to_unsafe
      {% begin %}
      case modulus.size
      {% for word_count in SPECIALIZED_WORD_COUNTS %}
      when {{ word_count }}
        {% if flag?(:aarch64) && !flag?(:beryl_portable_rsa) %}
          {% if word_count == 16 %}
            MontgomeryMultiplicationInAssembly.multiply_16(result_pointer, a_pointer, b_pointer, modulus_pointer, negated_inverse)
          {% else %}
            MontgomeryMultiplicationInAssembly.multiply_{{ word_count }}(result_pointer, a_pointer, b_pointer, modulus_pointer,
              negated_inverse, scratch[0, 2 * {{ word_count }} + 2].to_unsafe)
          {% end %}
        {% elsif flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
          if ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
            MontgomeryMultiplicationWithTwoCarryChains.multiply_{{ word_count }}(result_pointer, a_pointer, b_pointer,
              modulus_pointer, negated_inverse, scratch[0, multiplication_scratch_word_count({{ word_count }})].to_unsafe)
          else
            multiply_{{ word_count }}(result_pointer, a_pointer, b_pointer, modulus_pointer, negated_inverse, accumulator)
          end
        {% else %}
          multiply_{{ word_count }}(result_pointer, a_pointer, b_pointer, modulus_pointer, negated_inverse, accumulator)
        {% end %}
      {% end %}
      else
        multiply_any(result_pointer, a_pointer, b_pointer, modulus_pointer, negated_inverse, accumulator, modulus.size)
      end
      {% end %}
    end

    # Sets *result* to a·a/R mod *modulus* (*a* below it), the same as
    # `multiply(result, a, a, ...)`. *scratch* holds
    # `multiplication_scratch_word_count` words; *result* may be *a*. On
    # AArch64 the specialized word counts take the squarings of
    # `MontgomeryMultiplicationInAssembly`, which form each product
    # a_i·a_j once.
    def self.square(result : Slice(UInt64), a : Slice(UInt64), modulus : Slice(UInt64), negated_inverse : UInt64,
                    scratch : Slice(UInt64)) : Nil
      {% if flag?(:aarch64) && !flag?(:beryl_portable_rsa) %}
        {% begin %}
          case modulus.size
          when 16
            MontgomeryMultiplicationInAssembly.square_16(result.to_unsafe, a.to_unsafe, modulus.to_unsafe, negated_inverse,
              scratch[0, 32].to_unsafe)
            return
          {% for word_count in SPECIALIZED_WORD_COUNTS.reject { |count| count == 16 } %}
          when {{ word_count }}
            MontgomeryMultiplicationInAssembly.square_{{ word_count }}(result.to_unsafe, a.to_unsafe, modulus.to_unsafe,
              negated_inverse, scratch[0, 2 * {{ word_count }} + 2].to_unsafe)
            return
          {% end %}
          end
        {% end %}
      {% elsif flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
        if ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
          {% begin %}
            case modulus.size
            {% for word_count in SPECIALIZED_WORD_COUNTS %}
            when {{ word_count }}
              MontgomeryMultiplicationWithTwoCarryChains.square_{{ word_count }}(result.to_unsafe, a.to_unsafe, modulus.to_unsafe,
                negated_inverse, scratch[0, multiplication_scratch_word_count({{ word_count }})].to_unsafe)
              return
            {% end %}
            end
          {% end %}
        end
      {% end %}
      multiply(result, a, a, modulus, negated_inverse, scratch)
    end

    # The number of words of scratch `multiply` and `square` need for a
    # modulus of *word_count* words: on x86-64, the layout
    # `MontgomeryMultiplicationWithTwoCarryChains` describes.
    def self.multiplication_scratch_word_count(word_count : Int32) : Int32
      {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
        MontgomeryMultiplicationWithTwoCarryChains::SCRATCH_WORD_COUNT_PER_WORD * word_count +
          MontgomeryMultiplicationWithTwoCarryChains::SCRATCH_EXTRA_WORD_COUNT
      {% else %}
        2 * word_count + 2
      {% end %}
    end

    # The word counts of the moduli and primes of 2,048, 3,072 and 4,096-bit
    # keys. A copy of the multiplication is compiled for each, so that the
    # word count is a constant the optimizer can unroll the loops by; on
    # AArch64 the copies are the assembly of `MontgomeryMultiplicationInAssembly`.
    SPECIALIZED_WORD_COUNTS = [16, 24, 32, 48, 64]

    # The body of a Montgomery multiplication on raw word pointers, for
    # *word_count* words (a constant in each specialized copy).
    #
    # Finely integrated operand scanning: for each word of *b*, one pass
    # adds a·b[i] and u·m to the accumulator and shifts it down a word,
    # where u = (t[0] + a[0]·b[i])·(-m⁻¹) mod 2^64 clears the low word. The
    # accumulator stays below twice the modulus (n words and one bit), so
    # one subtraction, kept or dropped by mask, finishes the reduction.
    private macro montgomery_multiplication_body(word_count)
      {{ word_count }}.times { |index| accumulator[index] = 0_u64 }
      high_bit = 0_u64
      {{ word_count }}.times do |outer|
        b_word = b_pointer[outer].to_u128
        product = a_pointer[0].to_u128 &* b_word &+ accumulator[0].to_u128
        product_carry = (product >> 64).to_u64!
        factor = (product.to_u64! &* negated_inverse).to_u128
        reduction = modulus_pointer[0].to_u128 &* factor &+ product.to_u64!.to_u128
        reduction_carry = (reduction >> 64).to_u64!
        (1...{{ word_count }}).each do |inner|
          product = a_pointer[inner].to_u128 &* b_word &+ accumulator[inner].to_u128 &+ product_carry.to_u128
          product_carry = (product >> 64).to_u64!
          reduction = modulus_pointer[inner].to_u128 &* factor &+ product.to_u64!.to_u128 &+ reduction_carry.to_u128
          accumulator[inner - 1] = reduction.to_u64!
          reduction_carry = (reduction >> 64).to_u64!
        end
        top = high_bit.to_u128 &+ product_carry.to_u128 &+ reduction_carry.to_u128
        accumulator[{{ word_count }} - 1] = top.to_u64!
        high_bit = (top >> 64).to_u64!
      end
      subtract_modulus_when_not_below(Slice.new(result_pointer, {{ word_count }}), Slice.new(accumulator, {{ word_count }}),
        high_bit, Slice.new(modulus_pointer, {{ word_count }}))
    end

    {% for word_count in SPECIALIZED_WORD_COUNTS %}
      # :nodoc:
      def self.multiply_{{ word_count }}(result_pointer : UInt64*, a_pointer : UInt64*, b_pointer : UInt64*, modulus_pointer : UInt64*,
                                         negated_inverse : UInt64, accumulator : UInt64*) : Nil
        montgomery_multiplication_body({{ word_count }})
      end
    {% end %}

    # :nodoc:
    def self.multiply_any(result_pointer : UInt64*, a_pointer : UInt64*, b_pointer : UInt64*, modulus_pointer : UInt64*,
                          negated_inverse : UInt64, accumulator : UInt64*, word_count : Int32) : Nil
      montgomery_multiplication_body(word_count)
    end

    # Sets *result* to *value* minus *modulus* when the number made of
    # *value* and the extra high bit *high_bit* is at least the modulus,
    # and to *value* otherwise. *result* and *value* must not overlap.
    def self.subtract_modulus_when_not_below(result : Slice(UInt64), value : Slice(UInt64), high_bit : UInt64,
                                             modulus : Slice(UInt64)) : Nil
      result_pointer = result.to_unsafe
      value_pointer = value.to_unsafe
      modulus_pointer = modulus.to_unsafe
      borrow = 0_u64
      modulus.size.times do |index|
        difference = value_pointer[index].to_u128 &- modulus_pointer[index].to_u128 &- borrow.to_u128
        borrow = (difference >> 127).to_u64!
        result_pointer[index] = difference.to_u64!
      end
      keeps_difference = high_bit | (borrow ^ 1_u64)
      mask = mask_of(keeps_difference)
      modulus.size.times do |index|
        result_pointer[index] = (result_pointer[index] & mask) | (value_pointer[index] & ~mask)
      end
    end

    # Sets *result* to (a + b) mod *modulus*; *a* and *b* must be below it.
    # *result* may be *a* or *b*. *scratch* holds `modulus.size` words.
    def self.add(result : Slice(UInt64), a : Slice(UInt64), b : Slice(UInt64), modulus : Slice(UInt64),
                 scratch : Slice(UInt64)) : Nil
      carry = 0_u64
      modulus.size.times do |index|
        sum = a[index].to_u128 &+ b[index].to_u128 &+ carry.to_u128
        scratch[index] = sum.to_u64!
        carry = (sum >> 64).to_u64!
      end
      subtract_modulus_when_not_below(result, scratch[0, modulus.size], carry, modulus)
    end

    # Sets *result* to (a - b) mod *modulus*; *a* and *b* must be below it.
    # *result* may be *a* or *b*.
    def self.subtract(result : Slice(UInt64), a : Slice(UInt64), b : Slice(UInt64), modulus : Slice(UInt64)) : Nil
      borrow = 0_u64
      modulus.size.times do |index|
        difference = a[index].to_u128 &- b[index].to_u128 &- borrow.to_u128
        result[index] = difference.to_u64!
        borrow = (difference >> 127).to_u64!
      end
      mask = mask_of(borrow)
      carry = 0_u64
      modulus.size.times do |index|
        sum = result[index].to_u128 &+ (modulus[index] & mask).to_u128 &+ carry.to_u128
        result[index] = sum.to_u64!
        carry = (sum >> 64).to_u64!
      end
    end

    # Sets *result* to R² mod *modulus*, a modulus of *bit_count* bits (its
    # bit length, public), without dividing. 2^b mod m, for b the bit
    # length, is 2^b - m, which is -m mod 2^(64n) cut to its low b bits;
    # doubling that modulo m 64n + n - b times gives R·2^n mod m, and six
    # Montgomery squarings take R·2^a to R·2^(2a) each, ending at
    # R·2^(64n) = R² mod m. Starting from 2^b rather than from 1 saves about
    # 64n doublings. The modulus must be odd and above 1. *scratch* holds
    # `multiplication_scratch_word_count` words.
    def self.compute_r_squared(result : Slice(UInt64), modulus : Slice(UInt64), bit_count : Int32, negated_inverse : UInt64,
                               scratch : Slice(UInt64)) : Nil
      word_count = modulus.size
      borrow = 0_u64
      word_count.times do |index|
        difference = 0_u128 &- modulus[index].to_u128 &- borrow.to_u128
        result[index] = difference.to_u64!
        borrow = (difference >> 127).to_u64!
      end
      word_count.times do |index|
        low_bit = 64 * index
        if low_bit >= bit_count
          result[index] = 0_u64
        elsif bit_count - low_bit < 64
          result[index] &= (1_u64 << (bit_count - low_bit)) &- 1_u64
        end
      end
      # A modulus shorter than *bit_count* says (only the probes build one)
      # leaves the value above it; one subtraction keeps it in range there.
      result.copy_to(scratch[0, word_count])
      subtract_modulus_when_not_below(result, scratch[0, word_count], 0_u64, modulus)
      (64 * word_count + word_count - bit_count).times { double(result, modulus, scratch) }
      6.times { multiply(result, result, result, modulus, negated_inverse, scratch) }
    end

    # Sets *value* to 2·value mod *modulus*; *value* must be below it.
    def self.double(value : Slice(UInt64), modulus : Slice(UInt64), scratch : Slice(UInt64)) : Nil
      carried_bit = 0_u64
      value.size.times do |index|
        word = value[index]
        scratch[index] = (word << 1) | carried_bit
        carried_bit = word >> 63
      end
      subtract_modulus_when_not_below(value, scratch[0, value.size], carried_bit, modulus)
    end

    # Sets *result* to the Montgomery form of *value* modulo *modulus*,
    # where *value* may be longer than the modulus: Horner's rule over
    # chunks of `modulus.size` words, from the most significant, each
    # step multiplying by R and adding the next chunk, all in Montgomery
    # form (multiplying a chunk below R by R² mod m gives the chunk's
    # Montgomery form, reduced). Nothing is divided. *scratch* holds
    # `2 * modulus.size + multiplication_scratch_word_count` words.
    def self.reduce_to_montgomery_form(result : Slice(UInt64), value : Slice(UInt64), modulus : Slice(UInt64),
                                       r_squared : Slice(UInt64), negated_inverse : UInt64,
                                       scratch : Slice(UInt64)) : Nil
      word_count = modulus.size
      chunk = scratch[0, word_count]
      chunk_in_montgomery_form = scratch[word_count, word_count]
      multiplication_scratch = scratch[2 * word_count, multiplication_scratch_word_count(word_count)]
      chunk_count = (value.size + word_count - 1) // word_count
      result.fill(0_u64)
      (chunk_count - 1).downto(0) do |chunk_index|
        chunk_start = chunk_index * word_count
        chunk_word_count = Math.min(word_count, value.size - chunk_start)
        chunk.fill(0_u64)
        value[chunk_start, chunk_word_count].copy_to(chunk)
        multiply(chunk_in_montgomery_form, chunk, r_squared, modulus, negated_inverse, multiplication_scratch)
        multiply(result, result, r_squared, modulus, negated_inverse, multiplication_scratch)
        add(result, result, chunk_in_montgomery_form, modulus, multiplication_scratch)
      end
    end

    # The number of words of scratch `exponentiate` needs.
    def self.exponentiation_scratch_word_count(word_count : Int32) : Int32
      TABLE_ENTRY_COUNT * word_count + word_count + multiplication_scratch_word_count(word_count)
    end

    # Sets *result* to base^exponent·R mod *modulus* (the Montgomery form
    # of the power), given *base_in_montgomery_form* = base·R mod m. The
    # exponent is the big-endian *exponent*, secret; only its byte count
    # shows. Fixed window of `WINDOW_BIT_COUNT` bits: every window runs the
    # same squarings and one multiplication, by a table entry chosen by
    # reading all of the table and keeping one entry by mask.
    def self.exponentiate(result : Slice(UInt64), base_in_montgomery_form : Slice(UInt64), exponent : Bytes,
                          modulus : Slice(UInt64), r_squared : Slice(UInt64), negated_inverse : UInt64,
                          scratch : Slice(UInt64)) : Nil
      word_count = modulus.size
      table = scratch[0, TABLE_ENTRY_COUNT * word_count]
      selected = scratch[TABLE_ENTRY_COUNT * word_count, word_count]
      multiplication_scratch = scratch[TABLE_ENTRY_COUNT * word_count + word_count, multiplication_scratch_word_count(word_count)]

      # table[0] = R mod m (one, in Montgomery form), table[1] = base, each
      # even entry the square of the entry half its index, and each odd
      # entry the one before it times the base.
      one = selected
      one.fill(0_u64)
      one[0] = 1_u64
      multiply(table[0, word_count], one, r_squared, modulus, negated_inverse, multiplication_scratch)
      base_in_montgomery_form.copy_to(table[word_count, word_count])
      (2...TABLE_ENTRY_COUNT).each do |entry|
        if entry.even?
          square(table[entry * word_count, word_count], table[(entry // 2) * word_count, word_count], modulus,
            negated_inverse, multiplication_scratch)
        else
          multiply(table[entry * word_count, word_count], table[(entry - 1) * word_count, word_count],
            base_in_montgomery_form, modulus, negated_inverse, multiplication_scratch)
        end
      end

      table[0, word_count].copy_to(result)
      bit_count = exponent.size * 8
      window_count = (bit_count + WINDOW_BIT_COUNT - 1) // WINDOW_BIT_COUNT
      (window_count - 1).downto(0) do |window_index|
        WINDOW_BIT_COUNT.times { square(result, result, modulus, negated_inverse, multiplication_scratch) }
        window = window_bits(exponent, window_index * WINDOW_BIT_COUNT)
        select_table_entry(selected, table, window, word_count)
        multiply(result, result, selected, modulus, negated_inverse, multiplication_scratch)
      end
      SecretWiping.wipe(Bytes.new(scratch.to_unsafe.as(UInt8*), scratch.size * 8))
    end

    # Returns the `WINDOW_BIT_COUNT` bits of the big-endian *exponent* that
    # start *low_bit* bits above its least significant bit.
    @[AlwaysInline]
    def self.window_bits(exponent : Bytes, low_bit : Int32) : UInt64
      window = 0_u64
      WINDOW_BIT_COUNT.times do |offset|
        bit_position = low_bit + offset
        byte_index = exponent.size - 1 - bit_position // 8
        if byte_index >= 0
          window |= ((exponent[byte_index].to_u64 >> (bit_position % 8)) & 1_u64) << offset
        end
      end
      window
    end

    # Copies entry *window* of *table* into *selected*, reading every entry.
    @[AlwaysInline]
    def self.select_table_entry(selected : Slice(UInt64), table : Slice(UInt64), window : UInt64, word_count : Int32) : Nil
      {% if flag?(:aarch64) && !flag?(:beryl_portable_rsa) %}
        {% begin %}
          case word_count
          {% for count in SPECIALIZED_WORD_COUNTS %}
          when {{ count }}
            MontgomeryMultiplicationInAssembly.select_entry_{{ count }}(selected.to_unsafe, table.to_unsafe, window)
            return
          {% end %}
          end
        {% end %}
      {% elsif flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
        if ProcessorFeatures::HAS_AVX2
          {% begin %}
            case word_count
            {% for count in SPECIALIZED_WORD_COUNTS %}
            when {{ count }}
              MontgomeryMultiplicationWithTwoCarryChains.select_entry_{{ count }}(selected.to_unsafe, table.to_unsafe, window)
              return
            {% end %}
            end
          {% end %}
        end
      {% end %}
      selected_pointer = selected.to_unsafe
      table_pointer = table.to_unsafe
      word_count.times { |index| selected_pointer[index] = 0_u64 }
      TABLE_ENTRY_COUNT.times do |entry|
        mask = mask_of(zero_bit_of(window ^ entry.to_u64))
        entry_pointer = table_pointer + entry * word_count
        word_count.times { |index| selected_pointer[index] |= entry_pointer[index] & mask }
      end
    end

    # Sets *result* to base^exponent mod *modulus* for a public *exponent*
    # (an RSA public exponent) and a *base* below the modulus, by left to
    # right square and multiply: the base enters Montgomery form (a
    # multiplication by R²), and the power leaves it (a multiplication by
    # 1). Its time depends on the exponent's bits, which are public, and
    # not on the base. *scratch* holds
    # `public_exponentiation_scratch_word_count` words.
    def self.exponentiate_by_public_exponent(result : Slice(UInt64), base : Slice(UInt64), exponent : UInt64,
                                             modulus : Slice(UInt64), r_squared : Slice(UInt64),
                                             negated_inverse : UInt64, scratch : Slice(UInt64)) : Nil
      word_count = modulus.size
      base_in_montgomery_form = scratch[0, word_count]
      multiplication_scratch = scratch[word_count, multiplication_scratch_word_count(word_count)]
      multiply(base_in_montgomery_form, base, r_squared, modulus, negated_inverse, multiplication_scratch)
      base_in_montgomery_form.copy_to(result)
      highest_bit = 63 - exponent.leading_zeros_count
      (highest_bit - 1).downto(0) do |bit_position|
        square(result, result, modulus, negated_inverse, multiplication_scratch)
        if (exponent >> bit_position) & 1_u64 == 1_u64
          multiply(result, result, base_in_montgomery_form, modulus, negated_inverse, multiplication_scratch)
        end
      end
      leave_montgomery_form(result, modulus, negated_inverse, scratch)
    end

    # `exponentiate_by_public_exponent` with one multiplication fewer, for
    # a key used more than once: left to right square and multiply on the
    # plain base, with no conversion into Montgomery form. A Montgomery
    # square or product of values of the form x^k/R^(k-1) keeps that form
    # (x^(2k)/R^(2k-1), x^(k+1)/R^k), so the chain ends at x^e/R^(e-1), and
    # one multiplication by *correction* = R^e mod m
    # (`compute_public_exponent_correction`) gives x^e mod m.
    def self.exponentiate_by_public_exponent_with_correction(result : Slice(UInt64), base : Slice(UInt64), exponent : UInt64,
                                                             modulus : Slice(UInt64), correction : Slice(UInt64),
                                                             negated_inverse : UInt64, scratch : Slice(UInt64)) : Nil
      word_count = modulus.size
      multiplication_scratch = scratch[word_count, multiplication_scratch_word_count(word_count)]
      plain_base = scratch[0, word_count]
      base.copy_to(plain_base)
      plain_base.copy_to(result)
      highest_bit = 63 - exponent.leading_zeros_count
      (highest_bit - 1).downto(0) do |bit_position|
        square(result, result, modulus, negated_inverse, multiplication_scratch)
        if (exponent >> bit_position) & 1_u64 == 1_u64
          multiply(result, result, plain_base, modulus, negated_inverse, multiplication_scratch)
        end
      end
      multiply(result, result, correction, modulus, negated_inverse, multiplication_scratch)
    end

    # Sets *result* to R^exponent mod *modulus*, the correction
    # `exponentiate_by_public_exponent_with_correction` multiplies by: R² mod m is the
    # Montgomery form of R, its Montgomery power is the Montgomery form of
    # R^e, and leaving Montgomery form gives R^e mod m. The exponent is
    # public. *scratch* holds `public_exponentiation_scratch_word_count`
    # words.
    def self.compute_public_exponent_correction(result : Slice(UInt64), exponent : UInt64, modulus : Slice(UInt64),
                                                r_squared : Slice(UInt64), negated_inverse : UInt64,
                                                scratch : Slice(UInt64)) : Nil
      word_count = modulus.size
      multiplication_scratch = scratch[word_count, multiplication_scratch_word_count(word_count)]
      r_squared.copy_to(result)
      highest_bit = 63 - exponent.leading_zeros_count
      (highest_bit - 1).downto(0) do |bit_position|
        square(result, result, modulus, negated_inverse, multiplication_scratch)
        if (exponent >> bit_position) & 1_u64 == 1_u64
          multiply(result, result, r_squared, modulus, negated_inverse, multiplication_scratch)
        end
      end
      leave_montgomery_form(result, modulus, negated_inverse, scratch)
    end

    # The number of words of scratch `exponentiate_by_public_exponent` and
    # `leave_montgomery_form` need.
    def self.public_exponentiation_scratch_word_count(word_count : Int32) : Int32
      word_count + multiplication_scratch_word_count(word_count)
    end

    # Sets *value* (in Montgomery form) to its plain form: a Montgomery
    # multiplication by 1. *scratch* holds
    # `public_exponentiation_scratch_word_count` words.
    def self.leave_montgomery_form(value : Slice(UInt64), modulus : Slice(UInt64), negated_inverse : UInt64,
                                   scratch : Slice(UInt64)) : Nil
      word_count = modulus.size
      one = scratch[0, word_count]
      one.fill(0_u64)
      one[0] = 1_u64
      multiply(value, value, one, modulus, negated_inverse, scratch[word_count, multiplication_scratch_word_count(word_count)])
    end

    # Sets *result* (`a.size + b.size` words) to the full product a·b.
    def self.multiply_without_reduction(result : Slice(UInt64), a : Slice(UInt64), b : Slice(UInt64)) : Nil
      result.fill(0_u64)
      b.size.times do |outer|
        b_word = b[outer].to_u128
        carry = 0_u64
        a.size.times do |inner|
          product = a[inner].to_u128 &* b_word &+ result[outer + inner].to_u128 &+ carry.to_u128
          result[outer + inner] = product.to_u64!
          carry = (product >> 64).to_u64!
        end
        result[outer + a.size] = carry
      end
    end
  end
end
