require "../processor_features"
require "./p256_field"
require "./p256_scalar_field"
require "./p384_field"
require "./p384_scalar_field"

module Amber::Beryl::Crypto::FieldArithmetic
  # :nodoc:
  #
  # Montgomery multiplication, squaring, addition and subtraction written in
  # assembly for AArch64 and x86-64, for the prime-order curves (milestone
  # F3 of plans/BERYL_TLS_CRYPTO.md). The fiat-crypto translations are
  # correct and constant time, but LLVM compiles their carry chains through
  # 128-bit integers into about twice the instructions a hand-written chain
  # of `adds`/`adcs` (or `add`/`adc`) needs.
  #
  # Each function returns exactly what the fiat-crypto function of the same
  # name returns, for every input inside fiat-crypto's input bounds (every
  # value of every limb), so the curve code may use either.
  # spec/field_arithmetic/fiat_crypto_equality.cr checks that against
  # fiat-crypto's own C, as it checks the translations. Why the results
  # match bit for bit: a word-by-word Montgomery multiplication adds the
  # unique multiple M·p, 0 <= M < 2^(64n), that makes a·b + M·p divisible by
  # 2^(64n) (M is fixed by a·b mod 2^(64n) alone), divides, and subtracts
  # p once when the quotient is at least p. Whether the product is reduced
  # word by word as it is formed or after it is complete, the quotient is
  # the same integer, and so is the result.
  #
  # Constant time: the assembly has no branch and no memory address computed
  # from data; a result is chosen with `csel` (AArch64) or `cmovnc` (x86-64),
  # which do not branch. `mul`, `umulh` and `mulq` take a fixed time on the
  # processors Beryl supports (with Data Independent Timing on, on Arm).
  # `scripts/check_secret_flow.rb` checks the text of every statement.
  #
  # Clobber names are per processor, and LLVM drops a name it does not know
  # without a word: the condition flags are "cc" on AArch64 and "flags" on
  # x86-64. Milestone F3 first gave the x86-64 multiplication "cc"; LLVM
  # took the flags as untouched by the statement, and in --release builds
  # its scheduler placed the statement between a `subq` of fiat-crypto's
  # subtraction and the `sbbq` that reads its borrow, so a point addition
  # computed a wrong Y and ECDH gave wrong shared secrets (a debug build, or
  # the multiplication tested alone, never interleaves them).
  # `scripts/check_secret_flow.rb` now refuses any statement whose
  # instructions write the flags without the processor's flags clobber.
  #
  # -Dberyl_portable_curves builds the fiat-crypto translations alone, as CI
  # does once to keep that path tested.
  module FieldsInAssembly
    # Words 1 and 3 of the P-256 prime (words 0 and 2 are all ones and
    # zero), passed to the assembly as operands, so the compiler builds them
    # once for a run of field operations instead of each statement building
    # them.
    P256_PRIME_WORD_1 = 0x00000000ffffffff_u64
    P256_PRIME_WORD_3 = 0xffffffff00000001_u64

    {% if (flag?(:aarch64) || flag?(:x86_64)) && !flag?(:beryl_portable_curves) %}
      AVAILABLE = true
    {% else %}
      AVAILABLE = false
    {% end %}

    # Returns a/2 mod *modulus* for *a* below the odd *modulus* (little-endian
    # words): a + modulus when a is odd, which is even, shifted right one
    # bit. Constant time: the parity becomes a mask.
    @[AlwaysInline]
    def self.half_portable(a : StaticArray(UInt64, N), modulus : StaticArray(UInt64, N)) : StaticArray(UInt64, N) forall N
      # The empty assembly is a value barrier: without it the optimizer
      # turns the mask back into a branch on the parity.
      mask = 0_u64 &- (a.unsafe_fetch(0) & 1_u64)
      asm("" : "=r"(mask) : "0"(mask))
      sum = StaticArray(UInt64, N).new(0_u64)
      sum_pointer = sum.to_unsafe
      carry = 0_u64
      N.times do |index|
        total = a.unsafe_fetch(index).to_u128 &+ (modulus.unsafe_fetch(index) & mask).to_u128 &+ carry.to_u128
        sum_pointer[index] = total.to_u64!
        carry = (total >> 64).to_u64!
      end
      result = StaticArray(UInt64, N).new(0_u64)
      result_pointer = result.to_unsafe
      (N - 1).times { |index| result_pointer[index] = (sum_pointer[index] >> 1) | (sum_pointer[index + 1] << 63) }
      result_pointer[N - 1] = (sum_pointer[N - 1] >> 1) | (carry << 63)
      result
    end

    # Defines, in the module it is called in, the fiat-crypto functions the
    # curve code uses that have no assembly: they are fast already.
    macro forward_to_fiat_crypto(fiat_module)
      @[AlwaysInline]
      def self.set_one : Limbs
        {{ fiat_module }}.set_one
      end

      @[AlwaysInline]
      def self.selectznz(condition : UInt64, zero_case : Limbs, nonzero_case : Limbs) : Limbs
        {{ fiat_module }}.selectznz(condition, zero_case, nonzero_case)
      end

      @[AlwaysInline]
      def self.nonzero(element : Limbs) : UInt64
        {{ fiat_module }}.nonzero(element)
      end

      @[AlwaysInline]
      def self.to_montgomery(element : Limbs) : Limbs
        {{ fiat_module }}.to_montgomery(element)
      end

      @[AlwaysInline]
      def self.from_montgomery(element : Limbs) : Limbs
        {{ fiat_module }}.from_montgomery(element)
      end

      @[AlwaysInline]
      def self.subborrowx_u64(borrow : UInt64, first : UInt64, second : UInt64) : {UInt64, UInt64}
        {{ fiat_module }}.subborrowx_u64(borrow, first, second)
      end
    end

    # The text of an AArch64 Montgomery multiplication modulo the P-256
    # prime, on operands: $0 to $7 the eight words of the product (the low
    # four end as the result), $8 to $11 scratch, $12 to $15 the words of a
    # and $16 to $19 the words of b (both little-endian). *square* builds
    # a squaring instead, which forms each cross product a_i·a_j once and
    # doubles the sum by shifting it a bit (`extr`), not by adding it to
    # itself; it reads only $12 to $15.
    #
    # The low half of the product is reduced word by word: for P-256,
    # -p^-1 = 1 mod 2^64, so the multiplier of each step is the low word w
    # itself, and w·p = w·2^256 - w·2^224 + w·2^192 + w·2^96 - w: adding it
    # and dropping the low word adds w·2^32 to the next word (two shifts)
    # and w·(2^64 - 2^32 + 1) to the two above it. That product is formed
    # with `mul` and `umulh` by word 3 of p ($21) rather than as
    # (w << 64) - (w << 32) + w with `subs` and `sbc`: Apple's cores run
    # about three flag-setting instructions per cycle and two
    # multiplications, and the curve arithmetic is limited by the flags. The reduced low half (below p + 1) plus the high
    # half is below 2^257, and one conditional subtraction of p ends it.
    macro p256_aarch64_statement(square, first_factor, second_factor)
      {%
        product = (0..7).map { |index| "$#{index}" }
        scratch = (8..11).map { |index| "$#{index}" }
        a_words = (12..15).map { |index| "$#{index}" }
        b_words = (16..19).map { |index| "$#{index}" }
        lines = [] of StringLiteral
      %}
      {% if square %}
        {%
          lines << "mul #{product[1].id}, #{a_words[0].id}, #{a_words[1].id}"
          lines << "umulh #{scratch[0].id}, #{a_words[0].id}, #{a_words[1].id}"
          lines << "mul #{product[2].id}, #{a_words[0].id}, #{a_words[2].id}"
          lines << "umulh #{scratch[1].id}, #{a_words[0].id}, #{a_words[2].id}"
          lines << "mul #{product[3].id}, #{a_words[0].id}, #{a_words[3].id}"
          lines << "umulh #{product[4].id}, #{a_words[0].id}, #{a_words[3].id}"
          lines << "adds #{product[2].id}, #{product[2].id}, #{scratch[0].id}"
          lines << "adcs #{product[3].id}, #{product[3].id}, #{scratch[1].id}"
          lines << "adc #{product[4].id}, #{product[4].id}, xzr"
          lines << "mul #{scratch[0].id}, #{a_words[1].id}, #{a_words[2].id}"
          lines << "umulh #{scratch[1].id}, #{a_words[1].id}, #{a_words[2].id}"
          lines << "mul #{scratch[2].id}, #{a_words[1].id}, #{a_words[3].id}"
          lines << "umulh #{product[5].id}, #{a_words[1].id}, #{a_words[3].id}"
          lines << "adds #{scratch[1].id}, #{scratch[1].id}, #{scratch[2].id}"
          lines << "adc #{product[5].id}, #{product[5].id}, xzr"
          lines << "adds #{product[3].id}, #{product[3].id}, #{scratch[0].id}"
          lines << "adcs #{product[4].id}, #{product[4].id}, #{scratch[1].id}"
          lines << "adc #{product[5].id}, #{product[5].id}, xzr"
          lines << "mul #{scratch[0].id}, #{a_words[2].id}, #{a_words[3].id}"
          lines << "umulh #{product[6].id}, #{a_words[2].id}, #{a_words[3].id}"
          lines << "adds #{product[5].id}, #{product[5].id}, #{scratch[0].id}"
          lines << "adc #{product[6].id}, #{product[6].id}, xzr"
          lines << "lsr #{product[7].id}, #{product[6].id}, #63"
        %}
        {% for index in [6, 5, 4, 3, 2] %}
          {% lines << "extr #{product[index].id}, #{product[index].id}, #{product[index - 1].id}, #63" %}
        {% end %}
        {%
          lines << "lsl #{product[1].id}, #{product[1].id}, #1"
          lines << "mul #{product[0].id}, #{a_words[0].id}, #{a_words[0].id}"
          lines << "umulh #{scratch[0].id}, #{a_words[0].id}, #{a_words[0].id}"
          lines << "mul #{scratch[1].id}, #{a_words[1].id}, #{a_words[1].id}"
          lines << "umulh #{scratch[2].id}, #{a_words[1].id}, #{a_words[1].id}"
          lines << "adds #{product[1].id}, #{product[1].id}, #{scratch[0].id}"
          lines << "adcs #{product[2].id}, #{product[2].id}, #{scratch[1].id}"
          lines << "adcs #{product[3].id}, #{product[3].id}, #{scratch[2].id}"
          lines << "mul #{scratch[0].id}, #{a_words[2].id}, #{a_words[2].id}"
          lines << "umulh #{scratch[1].id}, #{a_words[2].id}, #{a_words[2].id}"
          lines << "mul #{scratch[2].id}, #{a_words[3].id}, #{a_words[3].id}"
          lines << "umulh #{scratch[3].id}, #{a_words[3].id}, #{a_words[3].id}"
          lines << "adcs #{product[4].id}, #{product[4].id}, #{scratch[0].id}"
          lines << "adcs #{product[5].id}, #{product[5].id}, #{scratch[1].id}"
          lines << "adcs #{product[6].id}, #{product[6].id}, #{scratch[2].id}"
          lines << "adc #{product[7].id}, #{product[7].id}, #{scratch[3].id}"
        %}
      {% else %}
        {% for column in 0..3 %}
          {% lines << "mul #{product[column].id}, #{a_words[0].id}, #{b_words[column].id}" %}
        {% end %}
        {% for column in 0..3 %}
          {% lines << "umulh #{scratch[column].id}, #{a_words[0].id}, #{b_words[column].id}" %}
        {% end %}
        {%
          lines << "adds #{product[1].id}, #{product[1].id}, #{scratch[0].id}"
          lines << "adcs #{product[2].id}, #{product[2].id}, #{scratch[1].id}"
          lines << "adcs #{product[3].id}, #{product[3].id}, #{scratch[2].id}"
          lines << "adc #{product[4].id}, #{scratch[3].id}, xzr"
        %}
        {% for row in 1..3 %}
          {% for column in 0..3 %}
            {% lines << "mul #{scratch[column].id}, #{a_words[row].id}, #{b_words[column].id}" %}
          {% end %}
          {% lines << "adds #{product[row].id}, #{product[row].id}, #{scratch[0].id}" %}
          {% for column in 1..3 %}
            {% lines << "adcs #{product[row + column].id}, #{product[row + column].id}, #{scratch[column].id}" %}
          {% end %}
          {% lines << "adc #{product[row + 4].id}, xzr, xzr" %}
          {% for column in 0..3 %}
            {% lines << "umulh #{scratch[column].id}, #{a_words[row].id}, #{b_words[column].id}" %}
          {% end %}
          {% lines << "adds #{product[row + 1].id}, #{product[row + 1].id}, #{scratch[0].id}" %}
          {% for column in 1..2 %}
            {% lines << "adcs #{product[row + 1 + column].id}, #{product[row + 1 + column].id}, #{scratch[column].id}" %}
          {% end %}
          {% lines << "adc #{product[row + 4].id}, #{product[row + 4].id}, #{scratch[3].id}" %}
        {% end %}
      {% end %}
      {% low = [product[0], product[1], product[2], product[3]] %}
      {% for step in 0..3 %}
        {%
          word = low[0]
          lines << "lsl #{scratch[0].id}, #{word.id}, #32"
          lines << "lsr #{scratch[1].id}, #{word.id}, #32"
          lines << "mul #{scratch[2].id}, #{word.id}, $21"
          lines << "umulh #{scratch[3].id}, #{word.id}, $21"
          lines << "adds #{low[1].id}, #{low[1].id}, #{scratch[0].id}"
          lines << "adcs #{low[2].id}, #{low[2].id}, #{scratch[1].id}"
          lines << "adcs #{low[3].id}, #{low[3].id}, #{scratch[2].id}"
          lines << "adc #{word.id}, #{scratch[3].id}, xzr"
          low = [low[1], low[2], low[3], low[0]]
        %}
      {% end %}
      {%
        lines << "adds #{product[0].id}, #{product[0].id}, #{product[4].id}"
        lines << "adcs #{product[1].id}, #{product[1].id}, #{product[5].id}"
        lines << "adcs #{product[2].id}, #{product[2].id}, #{product[6].id}"
        lines << "adcs #{product[3].id}, #{product[3].id}, #{product[7].id}"
        lines << "adc #{product[4].id}, xzr, xzr"
        lines << "adds #{scratch[0].id}, #{product[0].id}, #1"
        lines << "sbcs #{scratch[1].id}, #{product[1].id}, $20"
        lines << "sbcs #{scratch[2].id}, #{product[2].id}, xzr"
        lines << "sbcs #{scratch[3].id}, #{product[3].id}, $21"
        lines << "sbcs xzr, #{product[4].id}, xzr"
      %}
      {% for index in 0..3 %}
        {% lines << "csel #{product[index].id}, #{product[index].id}, #{scratch[index].id}, lo" %}
      {% end %}
      product_0 = product_1 = product_2 = product_3 = product_4 = product_5 = product_6 = product_7 = 0_u64
      scratch_0 = scratch_1 = scratch_2 = scratch_3 = 0_u64
      asm({{ lines.join("\n") }} : "=&r"(product_0), "=&r"(product_1), "=&r"(product_2), "=&r"(product_3),
                                   "=&r"(product_4), "=&r"(product_5), "=&r"(product_6), "=&r"(product_7),
                                   "=&r"(scratch_0), "=&r"(scratch_1), "=&r"(scratch_2), "=&r"(scratch_3)
                                 : "r"({{ first_factor }}.unsafe_fetch(0)), "r"({{ first_factor }}.unsafe_fetch(1)), "r"({{ first_factor }}.unsafe_fetch(2)), "r"({{ first_factor }}.unsafe_fetch(3)),
                                   "r"({{ second_factor }}.unsafe_fetch(0)), "r"({{ second_factor }}.unsafe_fetch(1)), "r"({{ second_factor }}.unsafe_fetch(2)), "r"({{ second_factor }}.unsafe_fetch(3)),
                                   "r"(::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly::P256_PRIME_WORD_1), "r"(::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly::P256_PRIME_WORD_3)
                                 : "cc")
      StaticArray[product_0, product_1, product_2, product_3]
    end

    # The text of a run of P-256 field operations on x86-64, in one
    # statement, each operand a field element in memory at a fixed offset
    # from one of the statement's pointer operands ($0, $1, ...), so a whole
    # point doubling or addition runs without leaving the assembly.
    # *steps* lists {operation, destination, a, b}, each place a
    # {pointer, offset} pair, and *pointers* the pointer operands in order.
    # Operations, each returning what fiat-crypto's function returns:
    #
    # - "mul" (`mulq`, every x86-64 processor) and "mulx" (BMI2 and ADX:
    #   each row after the first adds its low halves on the `adcx` chain and
    #   its high halves on the `adox` chain, both cleared by `xorl`, as
    #   OpenSSL's `ecp_nistz256` does with ADX): the Montgomery product.
    #   For "mul" the 512-bit product lives in r8 to r15 (rax, rcx and rdx
    #   scratch) and the reduction is the one described for AArch64; "mulx"
    #   reduces one word after each row, as OpenSSL's `mul_montx` does, on
    #   a ring of six registers (the same m, so the same sum (T + m·p)/2^256).
    #   Then one conditional subtraction of p (`cmovnc`).
    # - "mulx_square": a·a with `mulx`, the six cross products once, doubled
    #   on the `adcx` chain while the four squares come in on the `adox`
    #   chain (b is not read).
    # - "add": the five-word sum, p subtracted, the sum kept when that
    #   borrows; "sub": a - b, p added under the mask of its borrow (`sbb`
    #   of a register from itself), p's top word built from the mask as
    #   (mask_low << 32) - mask.
    # - "csel": b where the mask word at the step's fifth place is all
    #   ones, else a (`xor` of their difference under the mask).
    # - "half": a/2 for a below p (no fiat-crypto counterpart; see
    #   `half_portable`): p added under the mask of a's low bit, the
    #   five-word sum shifted right one bit with `shrd`.
    #
    # Each operation reads all of a and b before it writes its destination,
    # so a destination may be one of its own operands. The statement writes
    # the flags, so it names the x86-64 clobber "flags" (see the module
    # comment).
    #
    # An addition, subtraction, halving or selection whose a is the
    # previous step's result takes a from the registers that step left it
    # in. With *scratch* (the name of a pointer operand, such as "$0"), a
    # result written to that pointer is not stored when no later step
    # reads it from memory before it is written again: the memory there is
    # the statement's own, and nothing reads it after the statement.
    macro p256_x86_64_sequence_statement(steps, pointers, scratch = nil)
      {%
        product = %w(%r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)
        lines = [] of StringLiteral
        previous_destination = nil
        previous_result = product
        chained_steps = [] of BoolLiteral
        last_destination = nil
      %}
      {% for step in steps %}
        {%
          chained_steps << (step[2] == last_destination && %w(add sub half csel).includes?(step[0]))
          last_destination = step[1]
        %}
      {% end %}
      {% for step, step_position in steps %}
        {%
          operation = step[0]
          destination = step[1]
          first = step[2]
          second = step[3]
          a_words = (0..3).map { |index| "#{first[1] + 8 * index}(#{first[0].id})" }
          b_words = (0..3).map { |index| "#{second[1] + 8 * index}(#{second[0].id})" }
          destination_words = (0..3).map { |index| "#{destination[1] + 8 * index}(#{destination[0].id})" }
          result = product
        %}
        {% if first == previous_destination && %w(add sub half csel).includes?(operation) %}
          {%
            # The first operand is the previous step's result, still in
            # registers: it is moved to r8 to r11 (from r12, r13, r8 and
            # r9 after `mulx`, in an order that overwrites no word still
            # to be moved) instead of loaded, and so is the second when it
            # is the same element.
            if previous_result[0] == "%r12"
              lines << "movq %r9, %r11"
              lines << "movq %r8, %r10"
              lines << "movq %r13, %r9"
              lines << "movq %r12, %r8"
            end
            a_words = [product[0], product[1], product[2], product[3]]
            if second == first
              b_words = a_words
            end
          %}
        {% end %}
        {% if operation == "mul" %}
          {%
            lines << "movq #{a_words[0].id}, %rax"
            lines << "mulq #{b_words[0].id}"
            lines << "movq %rax, %r8"
            lines << "movq %rdx, %r9"
          %}
          {% for column in 1..3 %}
            {%
              lines << "movq #{a_words[0].id}, %rax"
              lines << "mulq #{b_words[column].id}"
              lines << "addq %rax, #{product[column].id}"
              lines << "adcq $$0, %rdx"
              lines << "movq %rdx, #{product[column + 1].id}"
            %}
          {% end %}
          {% for row in 1..3 %}
            {%
              lines << "movq #{a_words[row].id}, %rax"
              lines << "mulq #{b_words[0].id}"
              lines << "addq %rax, #{product[row].id}"
              lines << "adcq $$0, %rdx"
              lines << "movq %rdx, %rcx"
            %}
            {% for column in 1..3 %}
              {%
                lines << "movq #{a_words[row].id}, %rax"
                lines << "mulq #{b_words[column].id}"
                lines << "addq %rcx, %rax"
                lines << "adcq $$0, %rdx"
                lines << "addq %rax, #{product[row + column].id}"
                lines << "adcq $$0, %rdx"
                lines << "movq %rdx, %rcx"
              %}
            {% end %}
            {% lines << "movq %rcx, #{product[row + 4].id}" %}
          {% end %}
        {% elsif operation == "mulx" %}
          {%
            # Word i of the running sum lives in ring[i % 6]; after row i
            # and its reduction step, words i + 1 to i + 5 are live.
            ring = %w(%r8 %r9 %r10 %r11 %r12 %r13)
            lines << "movabsq $$0xffffffff00000001, %r14"
            lines << "xorl %r15d, %r15d"
            lines << "movq #{a_words[0].id}, %rdx"
            lines << "mulxq #{b_words[0].id}, %r8, %r9"
            lines << "mulxq #{b_words[1].id}, %rax, %r10"
            lines << "addq %rax, %r9"
            lines << "mulxq #{b_words[2].id}, %rax, %r11"
            lines << "adcq %rax, %r10"
            lines << "mulxq #{b_words[3].id}, %rax, %r12"
            lines << "adcq %rax, %r11"
            lines << "adcq $$0, %r12"
            lines << "movq $$0, %r13"
          %}
          {% for row in 0..3 %}
            {% if row > 0 %}
              {%
                # Zeroes the word the row's top carry lands in, and with it
                # both carry flags.
                lines << "movq #{a_words[row].id}, %rdx"
                lines << "xorl #{ring[(row + 5) % 6].id}d, #{ring[(row + 5) % 6].id}d"
              %}
              {% for column in 0..3 %}
                {%
                  lines << "mulxq #{b_words[column].id}, %rax, %rcx"
                  lines << "adcxq %rax, #{ring[(row + column) % 6].id}"
                  lines << "adoxq %rcx, #{ring[(row + column + 1) % 6].id}"
                %}
              {% end %}
              {%
                lines << "adcxq %r15, #{ring[(row + 4) % 6].id}"
                lines << "adoxq %r15, #{ring[(row + 5) % 6].id}"
                lines << "adcxq %r15, #{ring[(row + 5) % 6].id}"
              %}
            {% end %}
            {%
              # Montgomery step: m = word row (-p^-1 = 1 modulo 2^64);
              # m·p = m·2^256 - m·2^224 + m·2^192 + m·2^96 - m, the low
              # word cancels, m·2^96 is (m << 32, m >> 32) one word up and
              # m·(2^64 - 2^32 + 1) lands three words up.
              word = ring[row % 6]
              lines << "movq #{word.id}, %rax"
              lines << "shlq $$32, %rax"
              lines << "movq #{word.id}, %rcx"
              lines << "shrq $$32, %rcx"
              lines << "movq #{word.id}, %rdx"
              lines << "mulxq %r14, #{word.id}, %rdx"
              lines << "addq %rax, #{ring[(row + 1) % 6].id}"
              lines << "adcq %rcx, #{ring[(row + 2) % 6].id}"
              lines << "adcq #{word.id}, #{ring[(row + 3) % 6].id}"
              lines << "adcq %rdx, #{ring[(row + 4) % 6].id}"
              lines << "adcq $$0, #{ring[(row + 5) % 6].id}"
            %}
          {% end %}
          {%
            # Words 4 to 7 (r12, r13, r8, r9) and the carry word 8 (r10):
            # p subtracted, the difference kept unless it borrows; the
            # result is stored from those four registers.
            result = %w(%r12 %r13 %r8 %r9)
            lines << "movl $$0xffffffff, %r15d"
            lines << "movq %r12, %rax"
            lines << "movq %r13, %rcx"
            lines << "movq %r8, %rdx"
            lines << "movq %r9, %r11"
            lines << "subq $$-1, %rax"
            lines << "sbbq %r15, %rcx"
            lines << "sbbq $$0, %rdx"
            lines << "sbbq %r14, %r11"
            lines << "sbbq $$0, %r10"
            lines << "cmovncq %rax, %r12"
            lines << "cmovncq %rcx, %r13"
            lines << "cmovncq %rdx, %r8"
            lines << "cmovncq %r11, %r9"
          %}
        {% elsif operation == "mulx_square" %}
          {%
            lines << "movq #{a_words[0].id}, %rdx"
            lines << "mulxq #{a_words[1].id}, %r9, %r10"
            lines << "mulxq #{a_words[2].id}, %rax, %r11"
            lines << "mulxq #{a_words[3].id}, %rcx, %r12"
            lines << "addq %rax, %r10"
            lines << "adcq %rcx, %r11"
            lines << "adcq $$0, %r12"
            lines << "movq #{a_words[1].id}, %rdx"
            lines << "xorl %eax, %eax"
            lines << "mulxq #{a_words[2].id}, %rax, %rcx"
            lines << "adcxq %rax, %r11"
            lines << "adoxq %rcx, %r12"
            lines << "mulxq #{a_words[3].id}, %rax, %r13"
            lines << "adcxq %rax, %r12"
            lines << "movl $$0, %ecx"
            lines << "adoxq %rcx, %r13"
            lines << "adcxq %rcx, %r13"
            lines << "movq #{a_words[2].id}, %rdx"
            lines << "mulxq #{a_words[3].id}, %rax, %r14"
            lines << "addq %rax, %r13"
            lines << "adcq $$0, %r14"
            lines << "movq #{a_words[0].id}, %rdx"
            lines << "xorl %ecx, %ecx"
            lines << "mulxq %rdx, %r8, %rax"
            lines << "adcxq %r9, %r9"
            lines << "adoxq %rax, %r9"
            lines << "movq #{a_words[1].id}, %rdx"
            lines << "mulxq %rdx, %rax, %rcx"
            lines << "adcxq %r10, %r10"
            lines << "adoxq %rax, %r10"
            lines << "adcxq %r11, %r11"
            lines << "adoxq %rcx, %r11"
            lines << "movq #{a_words[2].id}, %rdx"
            lines << "mulxq %rdx, %rax, %rcx"
            lines << "adcxq %r12, %r12"
            lines << "adoxq %rax, %r12"
            lines << "adcxq %r13, %r13"
            lines << "adoxq %rcx, %r13"
            lines << "movq #{a_words[3].id}, %rdx"
            lines << "mulxq %rdx, %rax, %r15"
            lines << "adcxq %r14, %r14"
            lines << "adoxq %rax, %r14"
            lines << "movl $$0, %ecx"
            lines << "adcxq %rcx, %r15"
            lines << "adoxq %rcx, %r15"
          %}
        {% elsif operation == "add" %}
          {%
            lines << "movl $$0xffffffff, %ecx"
            lines << "movabsq $$0xffffffff00000001, %rdx"
            lines << "movl $$0, %eax"
          %}
          {% for index in 0..3 %}
            {%
              lines << "movq #{a_words[index].id}, #{product[index].id}"
              lines << "#{(index == 0 ? "addq" : "adcq").id} #{b_words[index].id}, #{product[index].id}"
            %}
          {% end %}
          {%
            lines << "adcq $$0, %rax"
            lines << "movq %r8, %r12"
            lines << "movq %r9, %r13"
            lines << "movq %r10, %r14"
            lines << "movq %r11, %r15"
            lines << "subq $$-1, %r12"
            lines << "sbbq %rcx, %r13"
            lines << "sbbq $$0, %r14"
            lines << "sbbq %rdx, %r15"
            lines << "sbbq $$0, %rax"
            lines << "cmovncq %r12, %r8"
            lines << "cmovncq %r13, %r9"
            lines << "cmovncq %r14, %r10"
            lines << "cmovncq %r15, %r11"
          %}
        {% elsif operation == "sub" %}
          {% for index in 0..3 %}
            {%
              lines << "movq #{a_words[index].id}, #{product[index].id}"
              lines << "#{(index == 0 ? "subq" : "sbbq").id} #{b_words[index].id}, #{product[index].id}"
            %}
          {% end %}
          {%
            lines << "sbbq %rax, %rax"
            lines << "movl %eax, %ecx"
            lines << "movq %rcx, %rdx"
            lines << "shlq $$32, %rdx"
            lines << "subq %rax, %rdx"
            lines << "addq %rax, %r8"
            lines << "adcq %rcx, %r9"
            lines << "adcq $$0, %r10"
            lines << "adcq %rdx, %r11"
          %}
        {% elsif operation == "csel" %}
          {% mask_word = "#{step[4][1]}(#{step[4][0].id})" %}
          {% for index in 0..3 %}
            {%
              lines << "movq #{a_words[index].id}, #{product[index].id}"
              lines << "movq #{b_words[index].id}, %r12"
              lines << "xorq #{product[index].id}, %r12"
              lines << "andq #{mask_word.id}, %r12"
              lines << "xorq %r12, #{product[index].id}"
            %}
          {% end %}
        {% elsif operation == "half" %}
          {% for index in 0..3 %}
            {% lines << "movq #{a_words[index].id}, #{product[index].id}" %}
          {% end %}
          {%
            lines << "movq %r8, %rax"
            lines << "andq $$1, %rax"
            lines << "xorl %ecx, %ecx"
            lines << "subq %rax, %rcx"
            lines << "movl %ecx, %edx"
            lines << "movq %rdx, %rax"
            lines << "shlq $$32, %rax"
            lines << "subq %rcx, %rax"
            lines << "addq %rcx, %r8"
            lines << "adcq %rdx, %r9"
            lines << "adcq $$0, %r10"
            lines << "adcq %rax, %r11"
            lines << "sbbq %rcx, %rcx"
            lines << "shrdq $$1, %r9, %r8"
            lines << "shrdq $$1, %r10, %r9"
            lines << "shrdq $$1, %r11, %r10"
            lines << "shrdq $$1, %rcx, %r11"
          %}
        {% else %}
          {% raise "unknown P-256 operation #{operation}" %}
        {% end %}
        {% if operation == "mul" || operation == "mulx_square" %}
          {% low = [product[0], product[1], product[2], product[3]] %}
          {% if operation == "mulx_square" %}
            {%
              # With `mulx`, as OpenSSL's `__ecp_nistz256_sqr_montx`: rdx
              # holds p's top word, and m·(2^64 - 2^32 + 1) is one `mulx`.
              lines << "movabsq $$0xffffffff00000001, %rdx"
            %}
          {% end %}
          {% for step_index in 0..3 %}
            {% word = low[0] %}
            {% if operation == "mulx_square" %}
              {%
                lines << "movq #{word.id}, %rax"
                lines << "shlq $$32, %rax"
                lines << "movq #{word.id}, %rcx"
                lines << "shrq $$32, %rcx"
                lines << "addq %rax, #{low[1].id}"
                lines << "adcq %rcx, #{low[2].id}"
                lines << "mulxq #{word.id}, %rax, #{word.id}"
                lines << "adcq %rax, #{low[3].id}"
                lines << "adcq $$0, #{word.id}"
              %}
            {% else %}
              {%
                lines << "movq #{word.id}, %rax"
                lines << "shlq $$32, %rax"
                lines << "movq #{word.id}, %rdx"
                lines << "shrq $$32, %rdx"
                lines << "movq #{word.id}, %rcx"
                lines << "subq %rax, %rcx"
                lines << "sbbq %rdx, #{word.id}"
                lines << "addq %rax, #{low[1].id}"
                lines << "adcq %rdx, #{low[2].id}"
                lines << "adcq %rcx, #{low[3].id}"
                lines << "adcq $$0, #{word.id}"
              %}
            {% end %}
            {% low = [low[1], low[2], low[3], low[0]] %}
          {% end %}
          {%
            lines << "addq #{product[4].id}, #{product[0].id}"
            lines << "adcq #{product[5].id}, #{product[1].id}"
            lines << "adcq #{product[6].id}, #{product[2].id}"
            lines << "adcq #{product[7].id}, #{product[3].id}"
            lines << "movl $$0, %ecx"
            lines << "adcq $$0, %rcx"
          %}
          {% for index in 0..3 %}
            {% lines << "movq #{product[index].id}, #{product[index + 4].id}" %}
          {% end %}
          {%
            lines << "movl $$0xffffffff, %eax"
            lines << "movabsq $$0xffffffff00000001, %rdx"
            lines << "subq $$-1, #{product[4].id}"
            lines << "sbbq %rax, #{product[5].id}"
            lines << "sbbq $$0, #{product[6].id}"
            lines << "sbbq %rdx, #{product[7].id}"
            lines << "sbbq $$0, %rcx"
          %}
          {% for index in 0..3 %}
            {% lines << "cmovncq #{product[index + 4].id}, #{product[index].id}" %}
          {% end %}
        {% end %}
        {% store_needed = true %}
        {% if scratch && destination[0] == scratch %}
          {%
            store_needed = false
            settled = false
          %}
          {% for later_index in 0...steps.size %}
            {% if later_index > step_position && !settled %}
              {%
                later = steps[later_index]
                first_from_registers = chained_steps[later_index] && later_index == step_position + 1
                reads_memory = (later[2] == destination && !first_from_registers) ||
                               (later[3] == destination && !(first_from_registers && later[3] == later[2])) ||
                               (later[0] == "csel" && later[4] == destination)
                if reads_memory
                  store_needed = true
                  settled = true
                elsif later[1] == destination
                  settled = true
                end
              %}
            {% end %}
          {% end %}
        {% end %}
        {% if store_needed %}
          {% for index in 0..3 %}
            {% lines << "movq #{result[index].id}, #{destination_words[index].id}" %}
          {% end %}
        {% end %}
        {%
          previous_destination = destination
          previous_result = result
        %}
      {% end %}
      {% lines = lines.reject { |line| line.starts_with?("movq %") && line[5..-1].split(", ")[0] == line[5..-1].split(", ")[1] } %}
      asm({{ lines.join("\n") }}
        :: {% for pointer, index in pointers %}{% if index > 0 %}, {% end %}"r"({{ pointer }}){% end %}
        : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "memory", "flags")
    end

    # P-256 point arithmetic on x86-64 in one statement
    # (`p256_x86_64_sequence_statement`), the steps of `Point#double`
    # (OpenSSL's `ecp_nistz256_point_double`) *doublings* times and then,
    # when *other* is given, those of `Point#add_unchecked`
    # (add-1998-cmo-2, 12M + 4S) with the point at *other*. Points are X, Y
    # and Z, 32 bytes each; *scratch* holds 80 words for the values in
    # between (and the masks, below), and *wide* picks `mulx` over `mulq`.
    # A statement takes three pointers at most: with 11 registers named
    # as clobbered, a build that keeps the frame pointer has three left.
    #
    # The first doubling reads the point at *input*, if given, and every
    # later step works on the point at *state*, where the result is left.
    # Each doubling reads
    # its point for the last time before it writes X, Y and Z (Z after Z
    # is read), and the addition reads the first point before it writes
    # the sum, so the work is done in place.
    #
    # With *masks* true, words 72 to 74 of *scratch* hold three masks
    # (each all ones or zero) and words 76 to 79 zero, and the statement is
    # one window of `multiply_constant_time`: Y of
    # *other* is replaced by -Y under the first mask (in place), the sum by
    # *other* under the second (the running sum was infinity), and the
    # result by the doubled point under the third (the digit was zero), as
    # `signed_multiple` and `Point#replace_if` do.
    macro p256_x86_64_point_statement(wide, scratch, state, doublings, input = nil, other = nil, masks = false)
      {%
        multiply = wide ? "mulx" : "mul"
        square = wide ? "mulx_square" : "mul"
        state_x = {"$1", 0}
        state_y = {"$1", 32}
        state_z = {"$1", 64}
        slot = (0..17).map { |index| {"$0", 32 * index} }
        steps = [] of TupleLiteral
        pointers = [scratch, state]
        input_name = "$1"
        other_name = "$2"
        if input
          pointers = pointers + [input]
          input_name = "$2"
          other_name = "$3"
        end
      %}
      {% for round in 0...doublings %}
        {%
          x = round == 0 ? {input_name, 0} : state_x
          y = round == 0 ? {input_name, 32} : state_y
          z = round == 0 ? {input_name, 64} : state_z
          # Nine additions, subtractions and halvings take their first
          # operand from the step just before them, in registers (see
          # `p256_x86_64_sequence_statement`).
          steps = steps + [
            {"add", slot[0], y, y},
            {square, slot[1], z, z},
            {"add", slot[4], slot[1], x},
            {"sub", slot[5], x, slot[1]},
            {multiply, slot[6], slot[4], slot[5]},
            {"add", slot[7], slot[6], slot[6]},
            {"add", slot[7], slot[7], slot[6]},
            {multiply, slot[3], y, z},
            {"add", state_z, slot[3], slot[3]},
            {square, slot[2], slot[0], slot[0]},
            {multiply, slot[9], slot[2], x},
            {"add", slot[10], slot[9], slot[9]},
            {square, slot[11], slot[7], slot[7]},
            {"sub", state_x, slot[11], slot[10]},
            {square, slot[8], slot[2], slot[2]},
            {"half", slot[8], slot[8], slot[8]},
            {"sub", slot[12], slot[9], state_x},
            {multiply, slot[12], slot[12], slot[7]},
            {"sub", state_y, slot[12], slot[8]},
          ]
        %}
      {% end %}
      {% if other %}
        {%
          pointers = pointers + [other]
          x1 = doublings == 0 ? {input_name, 0} : state_x
          y1 = doublings == 0 ? {input_name, 32} : state_y
          z1 = doublings == 0 ? {input_name, 64} : state_z
          x2 = {other_name, 0}
          y2 = {other_name, 32}
          z2 = {other_name, 64}
          sum_x = masks ? slot[14] : state_x
          sum_y = masks ? slot[15] : state_y
          sum_z = masks ? slot[16] : state_z
        %}
        {% if masks %}
          {%
            negative = {"$0", 576}
            steps = steps + [
              {"sub", slot[17], {"$0", 608}, y2},
              {"csel", y2, y2, slot[17], negative},
            ]
          %}
        {% end %}
        {%
          # The steps of the two longest chains (through H and through R)
          # alternate, the products off them (Z1·Z2, S1·H^3, Z3) sit in the
          # serial tail, and five subtractions and additions take their
          # first operand from the step just before them, in registers.
          # The first point is read for the last time before the sum is
          # written.
          steps = steps + [
            {square, slot[0], z1, z1},
            {square, slot[1], z2, z2},
            {multiply, slot[2], x1, slot[1]},
            {multiply, slot[3], x2, slot[0]},
            {"sub", slot[6], slot[3], slot[2]},
            {multiply, slot[5], z1, slot[0]},
            {multiply, slot[4], z2, slot[1]},
            {square, slot[9], slot[6], slot[6]},
            {multiply, slot[4], y1, slot[4]},
            {multiply, slot[5], y2, slot[5]},
            {"sub", slot[7], slot[5], slot[4]},
            {multiply, slot[10], slot[6], slot[9]},
            {multiply, slot[11], slot[2], slot[9]},
            {"add", slot[13], slot[11], slot[11]},
            {square, slot[12], slot[7], slot[7]},
            {"sub", slot[12], slot[12], slot[10]},
            {"sub", sum_x, slot[12], slot[13]},
            {multiply, slot[8], z1, z2},
            {"sub", slot[15], slot[11], sum_x},
            {multiply, slot[13], slot[4], slot[10]},
            {multiply, sum_z, slot[8], slot[6]},
            {multiply, slot[15], slot[7], slot[15]},
            {"sub", sum_y, slot[15], slot[13]},
          ]
        %}
        {% if masks %}
          {%
            infinity = {"$0", 584}
            zero_digit = {"$0", 592}
            steps = steps + [
              {"csel", slot[14], slot[14], x2, infinity},
              {"csel", slot[15], slot[15], y2, infinity},
              {"csel", slot[16], slot[16], z2, infinity},
              {"csel", state_x, slot[14], state_x, zero_digit},
              {"csel", state_y, slot[15], state_y, zero_digit},
              {"csel", state_z, slot[16], state_z, zero_digit},
            ]
          %}
        {% end %}
      {% end %}
      ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_sequence_statement({{ steps }}, {{ pointers }}, "$0")
    end

    # The end of a P-256 point addition on x86-64 in one statement: the
    # steps of `Point#finish_addition` from *inputs*, five field elements
    # (U1, S1, H, R and Z1·Z2) in a row, with *scratch* (32 words); the
    # sum's X, Y and Z are words 20 to 31 of *scratch*.
    macro p256_x86_64_finish_addition_statement(wide, scratch, inputs)
      {%
        multiply = wide ? "mulx" : "mul"
        square = wide ? "mulx_square" : "mul"
        u1 = {"$1", 0}
        s1 = {"$1", 32}
        h = {"$1", 64}
        r = {"$1", 96}
        z1_z2 = {"$1", 128}
        slot = (0..7).map { |index| {"$0", 32 * index} }
        steps = [
          {square, slot[0], h, h},
          {multiply, slot[1], h, slot[0]},
          {multiply, slot[2], u1, slot[0]},
          {square, slot[3], r, r},
          {"sub", slot[3], slot[3], slot[1]},
          {"add", slot[4], slot[2], slot[2]},
          {"sub", slot[5], slot[3], slot[4]},
          {"sub", slot[6], slot[2], slot[5]},
          {multiply, slot[6], r, slot[6]},
          {multiply, slot[4], s1, slot[1]},
          {"sub", slot[6], slot[6], slot[4]},
          {multiply, slot[7], z1_z2, h},
        ]
      %}
      ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_sequence_statement({{ steps }}, [{{ scratch }}, {{ inputs }}])
    end

    # One P-256 field operation on x86-64 (`p256_x86_64_sequence_statement`):
    # *result* = *operation*(*a*, *b*), all three `Limbs` variables.
    macro p256_x86_64_statement(operation, result, a, b)
      ::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly.p256_x86_64_sequence_statement(
        [{ {{ operation }}, {"$0", 0}, {"$1", 0}, {"$2", 0} }],
        [pointerof({{ result }}), pointerof({{ a }}), pointerof({{ b }})])
    end

    # The text of an AArch64 Montgomery multiplication modulo any odd
    # modulus of four words, with every value in registers: $0 to $5 the
    # running sum, $6 and $7 scratch, $8 to $11 the result of the final
    # subtraction, then the inputs: $12 to $15 the words of a, $16 to $19
    # those of b, $20 to $23 those of the modulus and $24 -p^-1 mod 2^64.
    # The steps are those of `montgomery_aarch64_statement`.
    macro montgomery_in_registers_aarch64_statement(first_factor, second_factor, modulus, negated_inverse)
      {%
        sum = (0..5).map { |index| "$#{index}" }
        product = "$6"
        multiplier = "$7"
        difference = (8..11).map { |index| "$#{index}" }
        a_words = (12..15).map { |index| "$#{index}" }
        b_words = (16..19).map { |index| "$#{index}" }
        modulus_words = (20..23).map { |index| "$#{index}" }
        lines = [] of StringLiteral
      %}
      {% for index in 0..5 %}
        {% lines << "mov #{sum[index].id}, xzr" %}
      {% end %}
      {% for row in 0..3 %}
        {% for column in 0..3 %}
          {% lines << "mul #{product.id}, #{a_words[row].id}, #{b_words[column].id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column].id}, #{sum[column].id}, #{product.id}" %}
        {% end %}
        {% lines << "adcs #{sum[4].id}, #{sum[4].id}, xzr" %}
        {% lines << "adc #{sum[5].id}, xzr, xzr" %}
        {% for column in 0..3 %}
          {% lines << "umulh #{product.id}, #{a_words[row].id}, #{b_words[column].id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column + 1].id}, #{sum[column + 1].id}, #{product.id}" %}
        {% end %}
        {% lines << "adc #{sum[5].id}, #{sum[5].id}, xzr" %}
        {% lines << "mul #{multiplier.id}, #{sum[0].id}, $24" %}
        {% for column in 0..3 %}
          {% lines << "mul #{product.id}, #{multiplier.id}, #{modulus_words[column].id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column].id}, #{sum[column].id}, #{product.id}" %}
        {% end %}
        {% lines << "adcs #{sum[4].id}, #{sum[4].id}, xzr" %}
        {% lines << "adc #{sum[5].id}, #{sum[5].id}, xzr" %}
        {% for column in 0..3 %}
          {% lines << "umulh #{product.id}, #{multiplier.id}, #{modulus_words[column].id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column + 1].id}, #{sum[column + 1].id}, #{product.id}" %}
        {% end %}
        {% lines << "adc #{sum[5].id}, #{sum[5].id}, xzr" %}
        {% sum = sum[1..-1] + [sum[0]] %}
      {% end %}
      {% for column in 0..3 %}
        {% lines << "#{(column == 0 ? "subs" : "sbcs").id} #{difference[column].id}, #{sum[column].id}, #{modulus_words[column].id}" %}
      {% end %}
      {% lines << "sbcs xzr, #{sum[4].id}, xzr" %}
      {% for column in 0..3 %}
        {% lines << "csel #{sum[column].id}, #{sum[column].id}, #{difference[column].id}, lo" %}
      {% end %}
      sum_0 = sum_1 = sum_2 = sum_3 = sum_4 = sum_5 = product_word = multiplier_word = 0_u64
      difference_0 = difference_1 = difference_2 = difference_3 = 0_u64
      asm({{ lines.join("\n") }} : "=&r"(sum_0), "=&r"(sum_1), "=&r"(sum_2), "=&r"(sum_3), "=&r"(sum_4), "=&r"(sum_5),
                                   "=&r"(product_word), "=&r"(multiplier_word),
                                   "=&r"(difference_0), "=&r"(difference_1), "=&r"(difference_2), "=&r"(difference_3)
                                 : "r"({{ first_factor }}.unsafe_fetch(0)), "r"({{ first_factor }}.unsafe_fetch(1)),
                                   "r"({{ first_factor }}.unsafe_fetch(2)), "r"({{ first_factor }}.unsafe_fetch(3)),
                                   "r"({{ second_factor }}.unsafe_fetch(0)), "r"({{ second_factor }}.unsafe_fetch(1)),
                                   "r"({{ second_factor }}.unsafe_fetch(2)), "r"({{ second_factor }}.unsafe_fetch(3)),
                                   "r"({{ modulus }}.unsafe_fetch(0)), "r"({{ modulus }}.unsafe_fetch(1)),
                                   "r"({{ modulus }}.unsafe_fetch(2)), "r"({{ modulus }}.unsafe_fetch(3)), "r"({{ negated_inverse }})
                                 : "cc")
      {%
        # Each step moves the sum down one register; the low words of the
        # result are where the last step left them.
        result_names = sum.map { |name| "sum_" + name[1..-1] }
      %}
      StaticArray[{{ result_names[0].id }}, {{ result_names[1].id }}, {{ result_names[2].id }}, {{ result_names[3].id }}]
    end

    # The text of an x86-64 selection of entry *index* from *table*, a run
    # of *entry_count* entries of *word_count* words (even, at most 20),
    # into *destination*, with AVX2: each entry is read 32 bytes at a time
    # (16 for a last half), ANDed with a mask that is all ones for the entry
    # whose number equals *index* (`vpcmpeqq` of a counter against the
    # index, both broadcast) and zero for every other, and ORed into the
    # kept copy. Every entry is read and every merge runs, so the time does
    # not depend on *index*; an index past the table gives zeros. Registers:
    # ymm0 to ymm4 the kept copy, ymm11 the entry read, ymm12 the mask,
    # ymm13 the index, ymm14 the counter, ymm15 all ones (minus one in each
    # lane, which `vpsubq` turns into an increment).
    macro select_entry_avx2_statement(word_count, entry_count, destination, table, index)
      {%
        chunk_count = (word_count + 3) // 4
        lines = ["vmovq $2, %xmm13", "vpbroadcastq %xmm13, %ymm13", "vpcmpeqq %ymm15, %ymm15, %ymm15",
                 "vpxor %ymm14, %ymm14, %ymm14"]
      %}
      {% for chunk in 0...chunk_count %}
        {% lines << "vpxor %ymm#{chunk}, %ymm#{chunk}, %ymm#{chunk}" %}
      {% end %}
      {% for entry in 0...entry_count %}
        {% lines << "vpcmpeqq %ymm13, %ymm14, %ymm12" %}
        {% for chunk in 0...chunk_count %}
          {% register = (chunk * 4 + 4 <= word_count) ? "ymm" : "xmm" %}
          {%
            lines << "vpand #{entry * word_count * 8 + chunk * 32}($1), %#{register.id}12, %#{register.id}11"
            lines << "vpor %#{register.id}11, %#{register.id}#{chunk}, %#{register.id}#{chunk}"
          %}
        {% end %}
        {% lines << "vpsubq %ymm15, %ymm14, %ymm14" %}
      {% end %}
      {% for chunk in 0...chunk_count %}
        {% register = (chunk * 4 + 4 <= word_count) ? "ymm" : "xmm" %}
        {% lines << "vmovdqu %#{register.id}#{chunk}, #{chunk * 32}($0)" %}
      {% end %}
      {% lines << "vzeroupper" %}
      asm({{ lines.join("\n") }}
        :: "r"({{ destination }}), "r"({{ table }}), "r"({{ index }})
        : "ymm0", "ymm1", "ymm2", "ymm3", "ymm4", "ymm11", "ymm12", "ymm13", "ymm14", "ymm15", "memory")
    end

    # The text of an AArch64 selection of entry *index* from *table*, a run
    # of *entry_count* entries of *word_count* words (even, at most 18),
    # into *destination*, every entry from *first_entry* on read and none
    # skipped, on the vector registers: each entry is loaded 32 bytes at a time
    # (`ldp` of two q registers) and merged into the kept copy under a mask
    # with `bit` (bitwise insert if true), which is all ones for the entry
    # whose number equals *index* (`cmp`, `csel`, `dup`) and zero for every
    # other. Every entry is read and every merge runs, so the time does not
    # depend on *index*; an index past the table keeps zeros. This takes half
    # the instructions of a selection by `csel` on general registers, and
    # they run beside the field arithmetic, on the vector units. Registers: v16 to v24 the kept
    # copy, v25 and v26 the words loaded, v27 the mask; x15 all ones, x16
    # the address of the entry, x17 the mask.
    macro select_entry_vector_statement(word_count, entry_count, first_entry, destination, table, index)
      {%
        quad_count = word_count // 2
        kept = (16...(16 + quad_count)).map { |number| "v#{number}" }
        lines = ["mov x15, #-1"]
      %}
      {% for quad in 0...quad_count %}
        {% lines << "movi #{kept[quad].id}.16b, #0" %}
      {% end %}
      {% for entry in first_entry...entry_count %}
        {%
          lines << "cmp $2, ##{entry}"
          lines << "csel x17, x15, xzr, eq"
          lines << "dup v27.2d, x17"
          lines << "add x16, $1, ##{entry * word_count * 8}"
        %}
        {% for quad in (0...quad_count).to_a.select { |number| number % 2 == 0 } %}
          {% if quad + 1 < quad_count %}
            {%
              lines << "ldp q25, q26, [x16, ##{quad * 16}]"
              lines << "bit #{kept[quad].id}.16b, v25.16b, v27.16b"
              lines << "bit #{kept[quad + 1].id}.16b, v26.16b, v27.16b"
            %}
          {% else %}
            {%
              lines << "ldr q25, [x16, ##{quad * 16}]"
              lines << "bit #{kept[quad].id}.16b, v25.16b, v27.16b"
            %}
          {% end %}
        {% end %}
      {% end %}
      {% for quad in (0...quad_count).to_a.select { |number| number % 2 == 0 } %}
        {% if quad + 1 < quad_count %}
          {% lines << "stp q#{16 + quad}, q#{17 + quad}, [$0, ##{quad * 16}]" %}
        {% else %}
          {% lines << "str q#{16 + quad}, [$0, ##{quad * 16}]" %}
        {% end %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: "r"({{ destination }}), "r"({{ table }}), "r"({{ index }})
        : "x15", "x16", "x17", "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27",
          "memory", "cc")
    end

    # The text of an AArch64 Montgomery multiplication modulo any odd
    # modulus of *word_count* words, word by word (coarsely integrated
    # operand scanning): $0 points at the result, $1 at a, $2 at b, $3 at
    # the modulus, and $4 holds -p^-1 mod 2^64. Registers x0 to x17 and
    # x19 to x22 are scratch: the words of b, the running sum (word_count + 2
    # words) and four temporaries. The sum stays below 2p < 2^(64n + 1)
    # between steps, so one conditional subtraction ends it.
    macro montgomery_aarch64_statement(word_count, result, first_factor, second_factor, modulus, negated_inverse)
      {%
        registers = %w(x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 x16 x17 x19 x20 x21 x22)
        b_words = registers[0...word_count]
        sum = registers[word_count...(2 * word_count + 2)]
        temporary = registers[(2 * word_count + 2)...(2 * word_count + 6)]
        a_word = temporary[0]
        product = temporary[1]
        multiplier = temporary[2]
        modulus_word = temporary[3]
        lines = [] of StringLiteral
      %}
      {% for index in 0...word_count %}
        {% lines << "ldr #{b_words[index].id}, [$2, ##{8 * index}]" %}
      {% end %}
      {% for index in 0...(word_count + 2) %}
        {% lines << "mov #{sum[index].id}, xzr" %}
      {% end %}
      {% for row in 0...word_count %}
        {% lines << "ldr #{a_word.id}, [$1, ##{8 * row}]" %}
        {% for column in 0...word_count %}
          {% lines << "mul #{product.id}, #{a_word.id}, #{b_words[column].id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column].id}, #{sum[column].id}, #{product.id}" %}
        {% end %}
        {% lines << "adcs #{sum[word_count].id}, #{sum[word_count].id}, xzr" %}
        {% lines << "adc #{sum[word_count + 1].id}, xzr, xzr" %}
        {% for column in 0...word_count %}
          {% lines << "umulh #{product.id}, #{a_word.id}, #{b_words[column].id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column + 1].id}, #{sum[column + 1].id}, #{product.id}" %}
        {% end %}
        {% lines << "adc #{sum[word_count + 1].id}, #{sum[word_count + 1].id}, xzr" %}
        {% lines << "mul #{multiplier.id}, #{sum[0].id}, $4" %}
        {% for column in 0...word_count %}
          {% lines << "ldr #{modulus_word.id}, [$3, ##{8 * column}]" %}
          {% lines << "mul #{product.id}, #{multiplier.id}, #{modulus_word.id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column].id}, #{sum[column].id}, #{product.id}" %}
        {% end %}
        {% lines << "adcs #{sum[word_count].id}, #{sum[word_count].id}, xzr" %}
        {% lines << "adc #{sum[word_count + 1].id}, #{sum[word_count + 1].id}, xzr" %}
        {% for column in 0...word_count %}
          {% lines << "ldr #{modulus_word.id}, [$3, ##{8 * column}]" %}
          {% lines << "umulh #{product.id}, #{multiplier.id}, #{modulus_word.id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column + 1].id}, #{sum[column + 1].id}, #{product.id}" %}
        {% end %}
        {% lines << "adc #{sum[word_count + 1].id}, #{sum[word_count + 1].id}, xzr" %}
        {% sum = sum[1..-1] + [sum[0]] %}
      {% end %}
      {% for column in 0...word_count %}
        {% lines << "ldr #{modulus_word.id}, [$3, ##{8 * column}]" %}
        {% lines << "#{(column == 0 ? "subs" : "sbcs").id} #{b_words[column].id}, #{sum[column].id}, #{modulus_word.id}" %}
      {% end %}
      {% lines << "sbcs xzr, #{sum[word_count].id}, xzr" %}
      {% for column in 0...word_count %}
        {% lines << "csel #{sum[column].id}, #{sum[column].id}, #{b_words[column].id}, lo" %}
        {% lines << "str #{sum[column].id}, [$0, ##{8 * column}]" %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: "r"(pointerof({{ result }})), "r"(pointerof({{ first_factor }})), "r"(pointerof({{ second_factor }})), "r"(pointerof({{ modulus }})), "r"({{ negated_inverse }})
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
          "x16", "x17", "x19", "x20", "x21", "x22", "memory", "cc")
    end
  end

  # :nodoc:
  #
  # The P-256 field as the curve code uses it: fiat-crypto's `P256Field`,
  # with multiplication, squaring, addition, subtraction and negation in
  # assembly where `FieldsInAssembly` has them.
  module P256FieldWithAssembly
    alias Limbs = P256Field::Limbs

    {% if flag?(:aarch64) && !flag?(:beryl_portable_curves) %}
      @[AlwaysInline]
      def self.mul(a : Limbs, b : Limbs) : Limbs
        FieldsInAssembly.p256_aarch64_statement(false, a, b)
      end

      @[AlwaysInline]
      def self.square(a : Limbs) : Limbs
        FieldsInAssembly.p256_aarch64_statement(true, a, a)
      end

      # fiat-crypto's `add`: a + b, less p unless that borrows.
      @[AlwaysInline]
      def self.add(a : Limbs, b : Limbs) : Limbs
        sum_0 = sum_1 = sum_2 = sum_3 = carry = 0_u64
        difference_0 = difference_1 = difference_2 = difference_3 = 0_u64
        asm("adds $0, $9, $13
          adcs $1, $10, $14
          adcs $2, $11, $15
          adcs $3, $12, $16
          adc $4, xzr, xzr
          adds $5, $0, #1
          sbcs $6, $1, $17
          sbcs $7, $2, xzr
          sbcs $8, $3, $18
          sbcs xzr, $4, xzr
          csel $0, $0, $5, lo
          csel $1, $1, $6, lo
          csel $2, $2, $7, lo
          csel $3, $3, $8, lo" : "=&r"(sum_0), "=&r"(sum_1), "=&r"(sum_2), "=&r"(sum_3), "=&r"(carry),
                                 "=&r"(difference_0), "=&r"(difference_1), "=&r"(difference_2), "=&r"(difference_3)
                               : "r"(a.unsafe_fetch(0)), "r"(a.unsafe_fetch(1)), "r"(a.unsafe_fetch(2)), "r"(a.unsafe_fetch(3)),
                                 "r"(b.unsafe_fetch(0)), "r"(b.unsafe_fetch(1)), "r"(b.unsafe_fetch(2)), "r"(b.unsafe_fetch(3)),
                                 "r"(::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly::P256_PRIME_WORD_1), "r"(::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly::P256_PRIME_WORD_3)
                               : "cc")
        StaticArray[sum_0, sum_1, sum_2, sum_3]
      end

      # fiat-crypto's `sub`: a - b, plus p when that borrows.
      @[AlwaysInline]
      def self.sub(a : Limbs, b : Limbs) : Limbs
        difference_0 = difference_1 = difference_2 = difference_3 = mask = masked_1 = masked_3 = low_bit = 0_u64
        asm("subs $0, $8, $12
          sbcs $1, $9, $13
          sbcs $2, $10, $14
          sbcs $3, $11, $15
          sbc $4, xzr, xzr
          and $5, $4, #0xffffffff
          and $7, $4, #1
          orr $6, $7, $5, lsl #32
          adds $0, $0, $4
          adcs $1, $1, $5
          adcs $2, $2, xzr
          adc $3, $3, $6" : "=&r"(difference_0), "=&r"(difference_1), "=&r"(difference_2), "=&r"(difference_3),
                            "=&r"(mask), "=&r"(masked_1), "=&r"(masked_3), "=&r"(low_bit)
                          : "r"(a.unsafe_fetch(0)), "r"(a.unsafe_fetch(1)), "r"(a.unsafe_fetch(2)), "r"(a.unsafe_fetch(3)),
                            "r"(b.unsafe_fetch(0)), "r"(b.unsafe_fetch(1)), "r"(b.unsafe_fetch(2)), "r"(b.unsafe_fetch(3))
                          : "cc")
        StaticArray[difference_0, difference_1, difference_2, difference_3]
      end

      @[AlwaysInline]
      def self.opp(a : Limbs) : Limbs
        sub(Limbs.new(0_u64), a)
      end

      # a/2 mod p for a below p: p is added when a is odd (the mask comes
      # from the low bit, so the addition is the only flag work), and the
      # five-word sum is shifted right one bit with `extr`.
      @[AlwaysInline]
      def self.half(a : Limbs) : Limbs
        half_0 = half_1 = half_2 = half_3 = mask = masked_1 = masked_3 = sum_0 = sum_1 = sum_2 = sum_3 = top = 0_u64
        asm("and $4, $12, #1
          sub $4, xzr, $4
          and $5, $4, $16
          and $6, $4, $17
          adds $7, $12, $4
          adcs $8, $13, $5
          adcs $9, $14, xzr
          adcs $10, $15, $6
          adc $11, xzr, xzr
          extr $0, $8, $7, #1
          extr $1, $9, $8, #1
          extr $2, $10, $9, #1
          extr $3, $11, $10, #1" : "=&r"(half_0), "=&r"(half_1), "=&r"(half_2), "=&r"(half_3), "=&r"(mask),
                                   "=&r"(masked_1), "=&r"(masked_3), "=&r"(sum_0), "=&r"(sum_1), "=&r"(sum_2), "=&r"(sum_3),
                                   "=&r"(top)
                                 : "r"(a.unsafe_fetch(0)), "r"(a.unsafe_fetch(1)), "r"(a.unsafe_fetch(2)), "r"(a.unsafe_fetch(3)),
                                   "r"(::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly::P256_PRIME_WORD_1),
                                   "r"(::Amber::Beryl::Crypto::FieldArithmetic::FieldsInAssembly::P256_PRIME_WORD_3)
                                 : "cc")
        StaticArray[half_0, half_1, half_2, half_3]
      end
    {% elsif flag?(:x86_64) && !flag?(:beryl_portable_curves) %}
      # `mulx` where the processor has BMI2 and ADX (a constant read once
      # at start-up), else `mulq`.
      @[AlwaysInline]
      def self.mul(a : Limbs, b : Limbs) : Limbs
        if ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
          mul_with_wide_multiply(a, b)
        else
          mul_with_multiply(a, b)
        end
      end

      @[AlwaysInline]
      def self.square(a : Limbs) : Limbs
        if ::Amber::Beryl::Crypto::ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS
          square_with_wide_multiply(a)
        else
          mul_with_multiply(a, a)
        end
      end

      def self.mul_with_multiply(a : Limbs, b : Limbs) : Limbs
        result = uninitialized Limbs
        FieldsInAssembly.p256_x86_64_statement("mul", result, a, b)
        result
      end

      def self.mul_with_wide_multiply(a : Limbs, b : Limbs) : Limbs
        result = uninitialized Limbs
        FieldsInAssembly.p256_x86_64_statement("mulx", result, a, b)
        result
      end

      def self.square_with_wide_multiply(a : Limbs) : Limbs
        result = uninitialized Limbs
        FieldsInAssembly.p256_x86_64_statement("mulx_square", result, a, a)
        result
      end

      # fiat-crypto's `add`, in assembly.
      def self.add(a : Limbs, b : Limbs) : Limbs
        result = uninitialized Limbs
        FieldsInAssembly.p256_x86_64_statement("add", result, a, b)
        result
      end

      # fiat-crypto's `sub`, in assembly.
      def self.sub(a : Limbs, b : Limbs) : Limbs
        result = uninitialized Limbs
        FieldsInAssembly.p256_x86_64_statement("sub", result, a, b)
        result
      end

      @[AlwaysInline]
      def self.opp(a : Limbs) : Limbs
        sub(Limbs.new(0_u64), a)
      end

      # a/2 mod p for a below p, in assembly.
      def self.half(a : Limbs) : Limbs
        result = uninitialized Limbs
        FieldsInAssembly.p256_x86_64_statement("half", result, a, a)
        result
      end
    {% else %}
      @[AlwaysInline]
      def self.mul(a : Limbs, b : Limbs) : Limbs
        P256Field.mul(a, b)
      end

      @[AlwaysInline]
      def self.square(a : Limbs) : Limbs
        P256Field.square(a)
      end

      @[AlwaysInline]
      def self.add(a : Limbs, b : Limbs) : Limbs
        P256Field.add(a, b)
      end

      @[AlwaysInline]
      def self.sub(a : Limbs, b : Limbs) : Limbs
        P256Field.sub(a, b)
      end

      @[AlwaysInline]
      def self.opp(a : Limbs) : Limbs
        P256Field.opp(a)
      end

      @[AlwaysInline]
      def self.half(a : Limbs) : Limbs
        FieldsInAssembly.half_portable(a, PRIME_WORDS)
      end
    {% end %}

    # The prime as little-endian words, for `half`.
    PRIME_WORDS = StaticArray[0xffffffffffffffff_u64, FieldsInAssembly::P256_PRIME_WORD_1, 0_u64, FieldsInAssembly::P256_PRIME_WORD_3]

    FieldsInAssembly.forward_to_fiat_crypto(P256Field)
  end

  {% for fiat_module, settings in {P256ScalarField: {4, "0xccd1c8aaee00bc4f", "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"},
                                   P384Field:       {6, "0x100000001", "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff"},
                                   P384ScalarField: {6, "0x6ed46089e88fdc45", "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973"}} %}
    {% word_count = settings[0] %}
    # :nodoc:
    #
    # fiat-crypto's `{{ fiat_module }}`, with multiplication and squaring in
    # assembly on AArch64 (`FieldsInAssembly.montgomery_aarch64_statement`).
    module {{ fiat_module }}WithAssembly
      alias Limbs = {{ fiat_module }}::Limbs

      # The modulus as little-endian words, and -modulus^-1 mod 2^64, which
      # the assembly reads (spec/beryl/crypto/fields_in_assembly_spec.cr
      # checks both).
      MODULUS_WORDS = StaticArray[{% for index in 0...word_count %}{{ ("0x" + settings[2][((word_count - 1 - index) * 16)...((word_count - index) * 16)] + "_u64").id }}, {% end %}]
      NEGATED_MODULUS_INVERSE = {{ (settings[1] + "_u64").id }}

      {% if flag?(:aarch64) && !flag?(:beryl_portable_curves) && word_count == 4 %}
        @[AlwaysInline]
        def self.mul(a : Limbs, b : Limbs) : Limbs
          FieldsInAssembly.montgomery_in_registers_aarch64_statement(a, b, MODULUS_WORDS, NEGATED_MODULUS_INVERSE)
        end

        @[AlwaysInline]
        def self.square(a : Limbs) : Limbs
          mul(a, a)
        end
      {% elsif flag?(:aarch64) && !flag?(:beryl_portable_curves) %}
        def self.mul(a : Limbs, b : Limbs) : Limbs
          result = uninitialized Limbs
          modulus = MODULUS_WORDS
          FieldsInAssembly.montgomery_aarch64_statement({{ word_count }}, result, a, b, modulus, NEGATED_MODULUS_INVERSE)
          result
        end

        @[AlwaysInline]
        def self.square(a : Limbs) : Limbs
          mul(a, a)
        end
      {% else %}
        @[AlwaysInline]
        def self.mul(a : Limbs, b : Limbs) : Limbs
          {{ fiat_module }}.mul(a, b)
        end

        @[AlwaysInline]
        def self.square(a : Limbs) : Limbs
          {{ fiat_module }}.square(a)
        end
      {% end %}

      @[AlwaysInline]
      def self.add(a : Limbs, b : Limbs) : Limbs
        {{ fiat_module }}.add(a, b)
      end

      @[AlwaysInline]
      def self.sub(a : Limbs, b : Limbs) : Limbs
        {{ fiat_module }}.sub(a, b)
      end

      @[AlwaysInline]
      def self.opp(a : Limbs) : Limbs
        {{ fiat_module }}.opp(a)
      end

      # a/2 mod the modulus, for a below it.
      @[AlwaysInline]
      def self.half(a : Limbs) : Limbs
        FieldsInAssembly.half_portable(a, MODULUS_WORDS)
      end

      FieldsInAssembly.forward_to_fiat_crypto({{ fiat_module }})
    end
  {% end %}
end
