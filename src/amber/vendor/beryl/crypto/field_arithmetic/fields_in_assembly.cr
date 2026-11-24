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

    # The text of an x86-64 Montgomery multiplication modulo the P-256 prime
    # on memory: $0 points at the result, $1 at a, $2 at b. The product
    # words live in r8 to r15; rax, rdx and rcx are scratch. The reduction
    # is the one described for AArch64. The statement writes the flags, so
    # it names the x86-64 clobber "flags" (see the module comment).
    macro p256_x86_64_statement(result, a, b)
      {%
        product = %w(%r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)
        lines = [] of StringLiteral
        lines << "movq 0($1), %rax"
        lines << "mulq 0($2)"
        lines << "movq %rax, #{product[0].id}"
        lines << "movq %rdx, #{product[1].id}"
      %}
      {% for column in 1..3 %}
        {%
          lines << "movq 0($1), %rax"
          lines << "mulq #{8 * column}($2)"
          lines << "addq %rax, #{product[column].id}"
          lines << "adcq $$0, %rdx"
          lines << "movq %rdx, #{product[column + 1].id}"
        %}
      {% end %}
      {% for row in 1..3 %}
        {%
          lines << "movq #{8 * row}($1), %rax"
          lines << "mulq 0($2)"
          lines << "addq %rax, #{product[row].id}"
          lines << "adcq $$0, %rdx"
          lines << "movq %rdx, %rcx"
        %}
        {% for column in 1..3 %}
          {%
            lines << "movq #{8 * row}($1), %rax"
            lines << "mulq #{8 * column}($2)"
            lines << "addq %rcx, %rax"
            lines << "adcq $$0, %rdx"
            lines << "addq %rax, #{product[row + column].id}"
            lines << "adcq $$0, %rdx"
            lines << "movq %rdx, %rcx"
          %}
        {% end %}
        {% lines << "movq %rcx, #{product[row + 4].id}" %}
      {% end %}
      {% low = [product[0], product[1], product[2], product[3]] %}
      {% for step in 0..3 %}
        {%
          word = low[0]
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
          low = [low[1], low[2], low[3], low[0]]
        %}
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
      {% for index in 0..3 %}
        {% lines << "movq #{product[index].id}, #{8 * index}($0)" %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: "r"(pointerof({{ result }})), "r"(pointerof({{ a }})), "r"(pointerof({{ b }}))
        : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "memory", "flags")
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
      def self.mul(a : Limbs, b : Limbs) : Limbs
        result = uninitialized Limbs
        FieldsInAssembly.p256_x86_64_statement(result, a, b)
        result
      end

      @[AlwaysInline]
      def self.square(a : Limbs) : Limbs
        mul(a, a)
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
