require "./curve25519_solinas_field"

module Amber::Beryl::Crypto::FieldArithmetic
  # :nodoc:
  #
  # Arithmetic modulo p = 2^255 - 19 on four saturated 64-bit words, for the
  # X25519 ladder and Ed25519 verification: any 256-bit value stands for itself modulo p, and every
  # function takes any four words and returns four words, reduced modulo
  # 2^256 - 38 = 2·p but not below p. This is the representation of
  # OpenSSL's `x25519-x86_64` (radix 2^64) rather than fiat-crypto's five
  # 51-bit limbs: a product is 16 word multiplications instead of 25, and
  # with no limb headroom to track, any operation may follow any other.
  #
  # Multiplication and squaring return what fiat-crypto's
  # `fiat_curve25519_solinas_mul` and `_square` return
  # (`Curve25519SolinasField`, translated from fiat-crypto's JSON), for every
  # input: the 512-bit product H·2^256 + L becomes L + 38·H, whose top word
  # t is folded once more as 38·t, and a carry out of that adds 38 to the
  # low word (2^256 = 38 modulo 2^256 - 38). Every implementation below
  # computes that same function of the product, so the results are equal
  # bit for bit; spec/field_arithmetic/fiat_crypto_equality.cr checks it
  # against fiat-crypto's C.
  #
  # Addition, subtraction and the multiplication by 121666 have no
  # fiat-crypto function; each is the sum, difference or product folded the
  # same way (a carry out adds 38, a borrow out subtracts 38, a second one
  # adjusts the low word alone, which cannot carry or borrow again). The
  # equality spec checks the assembly against the portable Crystal
  # here bit for bit, and both against fiat-crypto's C `curve25519_64`
  # modulo p.
  #
  # The variants: `Portable` (Crystal on `UInt128`), `X86WithMultiply`
  # (`mulq`, every x86-64 processor), `X86WithWideMultiply` (`mulx`, `adcx`
  # and `adox`, two carry chains at once, where
  # `ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS`) and
  # `AArch64` (`mul`, `umulh`, `adds`/`adcs`). Constant time: no branch and
  # no address computed from data; carries become masks (`sbb` and `and`,
  # or `csel`). `scripts/check_secret_flow.rb` checks the text of every
  # statement.
  module Curve25519SolinasFieldWithAssembly
    alias Limbs = StaticArray(UInt64, 4)

    # Returns the 32 little-endian bytes as four words (all 256 bits kept).
    def self.from_bytes(bytes : StaticArray(UInt8, 32)) : Limbs
      words = Limbs.new(0_u64)
      32.times { |index| words[index >> 3] |= bytes[index].to_u64 << (8 * (index & 7)) }
      words
    end

    # Returns the four words as 32 little-endian bytes.
    def self.to_bytes(words : Limbs) : StaticArray(UInt8, 32)
      StaticArray(UInt8, 32).new { |index| (words[index >> 3] >> (8 * (index & 7))).to_u8! }
    end

    # p = 2^255 - 19, little-endian.
    PRIME_WORDS = StaticArray[0xffffffffffffffed_u64, 0xffffffffffffffff_u64, 0xffffffffffffffff_u64, 0x7fffffffffffffff_u64]

    # Returns the value below p that *a* stands for: a < 2^256 < 3·p, so
    # two conditional subtractions of p, each kept by mask.
    def self.canonical(a : Limbs) : Limbs
      2.times { a = subtract_prime_unless_below(a) }
      a
    end

    private def self.subtract_prime_unless_below(a : Limbs) : Limbs
      difference = Limbs.new(0_u64)
      borrow = 0_u64
      4.times do |index|
        full = a[index].to_u128 &- PRIME_WORDS[index].to_u128 &- borrow.to_u128
        difference[index] = full.to_u64!
        borrow = (full >> 127).to_u64!
      end
      keep_mask = Curve25519SolinasField.value_barrier(0_u64 &- borrow)
      Limbs.new { |index| (a[index] & keep_mask) | (difference[index] & ~keep_mask) }
    end

    # Swaps *first* and *second* when *bit* is 1, by mask.
    @[AlwaysInline]
    def self.conditional_swap(bit : UInt64, first : Limbs, second : Limbs) : {Limbs, Limbs}
      mask = Curve25519SolinasField.value_barrier(0_u64 &- bit)
      swapped_first = Limbs.new(0_u64)
      swapped_second = Limbs.new(0_u64)
      4.times do |index|
        difference = (first.unsafe_fetch(index) ^ second.unsafe_fetch(index)) & mask
        swapped_first[index] = first.unsafe_fetch(index) ^ difference
        swapped_second[index] = second.unsafe_fetch(index) ^ difference
      end
      {swapped_first, swapped_second}
    end

    # Crystal on `UInt128`: the reference for the assembly, and the code
    # where there is none (`-Dberyl_portable_curves`, other processors).
    module Portable
      alias Limbs = StaticArray(UInt64, 4)

      @[AlwaysInline]
      def self.mul(a : Limbs, b : Limbs) : Limbs
        Curve25519SolinasField.mul(a, b)
      end

      @[AlwaysInline]
      def self.square(a : Limbs) : Limbs
        Curve25519SolinasField.square(a)
      end

      # (a + b) folded: a carry out adds 38, and a second carry adds 38 to
      # the low word.
      def self.add(a : Limbs, b : Limbs) : Limbs
        sum = Limbs.new(0_u64)
        carry = 0_u64
        4.times do |index|
          full = a.unsafe_fetch(index).to_u128 &+ b.unsafe_fetch(index).to_u128 &+ carry.to_u128
          sum[index] = full.to_u64!
          carry = (full >> 64).to_u64!
        end
        fold_carry(sum, carry)
      end

      # (a - b) folded: a borrow out subtracts 38, and a second borrow
      # subtracts 38 from the low word.
      def self.sub(a : Limbs, b : Limbs) : Limbs
        difference = Limbs.new(0_u64)
        borrow = 0_u64
        4.times do |index|
          full = a.unsafe_fetch(index).to_u128 &- b.unsafe_fetch(index).to_u128 &- borrow.to_u128
          difference[index] = full.to_u64!
          borrow = (full >> 127).to_u64!
        end
        adjustment = Curve25519SolinasField.value_barrier(0_u64 &- borrow) & 38_u64
        borrow = 0_u64
        4.times do |index|
          full = difference.unsafe_fetch(index).to_u128 &- (index == 0 ? adjustment : 0_u64).to_u128 &- borrow.to_u128
          difference[index] = full.to_u64!
          borrow = (full >> 127).to_u64!
        end
        difference[0] = difference.unsafe_fetch(0) &- (Curve25519SolinasField.value_barrier(0_u64 &- borrow) & 38_u64)
        difference
      end

      # 121666·a folded: the fifth word t of the product adds 38·t.
      def self.scmul_121666(a : Limbs) : Limbs
        product = Limbs.new(0_u64)
        carry = 0_u64
        4.times do |index|
          full = a.unsafe_fetch(index).to_u128 &* 121666_u128 &+ carry.to_u128
          product[index] = full.to_u64!
          carry = (full >> 64).to_u64!
        end
        top = carry &* 38_u64
        sum = Limbs.new(0_u64)
        carry = 0_u64
        4.times do |index|
          full = product.unsafe_fetch(index).to_u128 &+ (index == 0 ? top : 0_u64).to_u128 &+ carry.to_u128
          sum[index] = full.to_u64!
          carry = (full >> 64).to_u64!
        end
        sum[0] = sum.unsafe_fetch(0) &+ (Curve25519SolinasField.value_barrier(0_u64 &- carry) & 38_u64)
        sum
      end

      private def self.fold_carry(sum : Limbs, carry : UInt64) : Limbs
        adjustment = Curve25519SolinasField.value_barrier(0_u64 &- carry) & 38_u64
        carry = 0_u64
        4.times do |index|
          full = sum.unsafe_fetch(index).to_u128 &+ (index == 0 ? adjustment : 0_u64).to_u128 &+ carry.to_u128
          sum[index] = full.to_u64!
          carry = (full >> 64).to_u64!
        end
        sum[0] = sum.unsafe_fetch(0) &+ (Curve25519SolinasField.value_barrier(0_u64 &- carry) & 38_u64)
        sum
      end
    end

    # The text of a run of field operations on x86-64, in one statement,
    # each operand four words in memory at a fixed offset from one of the
    # statement's pointer operands ($0, $1, ...), so a whole ladder step
    # runs without leaving the assembly (and without the processor having
    # to forward 8-byte stores into the wider loads compiled code would
    # copy them with). *steps* lists {operation, destination, a, b}, each
    # place a {pointer, offset} pair; *pointers* are the pointer operands in
    # order, and *mask*, if given, is one more operand after them, all ones
    # or zero, for "cswap". Operations:
    #
    # - "mul": the product, row by row with `mulq`, into r8 to r15;
    # - "wide_mul": the product with `mulx`, each row after the first adding
    #   its low halves on the `adcx` chain and its high halves on the `adox`
    #   chain (both cleared by `xorl`);
    # - "wide_square": the six cross products once, doubled on the `adcx`
    #   chain while the four squares come in on the `adox` chain;
    # - "scmul" and "wide_scmul": 121666·a, five words, with `mulq` or `mulx`;
    # - "add" and "sub": a ± b, a carry or borrow out folded as 38 (by mask),
    #   then a second one into the low word alone;
    # - "cswap": a and b exchanged where the mask is all ones (`xor` of
    #   their difference under the mask), in place; no destination.
    #
    # A product in r8 to r15 is folded to L + 38·H (the top word t in rcx or
    # r12), then 38·t is added and a carry out adds 38; the result, in r8 to
    # r11, is stored last, so a destination may be one of its operands. The
    # statement writes the flags, so it names the x86-64 clobber "flags".
    macro x86_64_sequence_statement(steps, pointers, mask = nil)
      {%
        lines = [] of StringLiteral
        product = %w(%r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15)
        mask_operand = "$#{pointers.size}"
      %}
      {% for step in steps %}
        {%
          operation = step[0]
          a = (0..3).map { |index| "#{step[2][1] + 8 * index}(#{step[2][0].id})" }
          b = (0..3).map { |index| "#{step[3][1] + 8 * index}(#{step[3][0].id})" }
          destination = step[1] ? (0..3).map { |index| "#{step[1][1] + 8 * index}(#{step[1][0].id})" } : nil
        %}
        {% if operation == "mul" %}
          {%
            lines << "movq #{a[0].id}, %rax"
            lines << "mulq #{b[0].id}"
            lines << "movq %rax, %r8"
            lines << "movq %rdx, %r9"
          %}
          {% for column in 1..3 %}
            {%
              lines << "movq #{a[0].id}, %rax"
              lines << "mulq #{b[column].id}"
              lines << "addq %rax, #{product[column].id}"
              lines << "adcq $$0, %rdx"
              lines << "movq %rdx, #{product[column + 1].id}"
            %}
          {% end %}
          {% for row in 1..3 %}
            {%
              lines << "movq #{a[row].id}, %rax"
              lines << "mulq #{b[0].id}"
              lines << "addq %rax, #{product[row].id}"
              lines << "adcq $$0, %rdx"
              lines << "movq %rdx, %rcx"
            %}
            {% for column in 1..3 %}
              {%
                lines << "movq #{a[row].id}, %rax"
                lines << "mulq #{b[column].id}"
                lines << "addq %rcx, %rax"
                lines << "adcq $$0, %rdx"
                lines << "addq %rax, #{product[row + column].id}"
                lines << "adcq $$0, %rdx"
                lines << "movq %rdx, %rcx"
              %}
            {% end %}
            {% lines << "movq %rcx, #{product[row + 4].id}" %}
          {% end %}
        {% elsif operation == "wide_mul" %}
          {%
            lines << "movq #{a[0].id}, %rdx"
            lines << "mulxq #{b[0].id}, %r8, %r9"
            lines << "mulxq #{b[1].id}, %rax, %r10"
            lines << "addq %rax, %r9"
            lines << "mulxq #{b[2].id}, %rax, %r11"
            lines << "adcq %rax, %r10"
            lines << "mulxq #{b[3].id}, %rax, %r12"
            lines << "adcq %rax, %r11"
            lines << "adcq $$0, %r12"
          %}
          {% for row in 1..3 %}
            {%
              lines << "movq #{a[row].id}, %rdx"
              lines << "xorl %eax, %eax"
            %}
            {% for column in 0..2 %}
              {%
                lines << "mulxq #{b[column].id}, %rax, %rcx"
                lines << "adcxq %rax, #{product[row + column].id}"
                lines << "adoxq %rcx, #{product[row + column + 1].id}"
              %}
            {% end %}
            {%
              lines << "mulxq #{b[3].id}, %rax, #{product[row + 4].id}"
              lines << "adcxq %rax, #{product[row + 3].id}"
              lines << "movl $$0, %ecx"
              lines << "adoxq %rcx, #{product[row + 4].id}"
              lines << "adcxq %rcx, #{product[row + 4].id}"
            %}
          {% end %}
        {% elsif operation == "wide_square" %}
          {%
            lines << "movq #{a[0].id}, %rdx"
            lines << "mulxq #{a[1].id}, %r9, %r10"
            lines << "mulxq #{a[2].id}, %rax, %r11"
            lines << "mulxq #{a[3].id}, %rcx, %r12"
            lines << "addq %rax, %r10"
            lines << "adcq %rcx, %r11"
            lines << "adcq $$0, %r12"
            lines << "movq #{a[1].id}, %rdx"
            lines << "xorl %eax, %eax"
            lines << "mulxq #{a[2].id}, %rax, %rcx"
            lines << "adcxq %rax, %r11"
            lines << "adoxq %rcx, %r12"
            lines << "mulxq #{a[3].id}, %rax, %r13"
            lines << "adcxq %rax, %r12"
            lines << "movl $$0, %ecx"
            lines << "adoxq %rcx, %r13"
            lines << "adcxq %rcx, %r13"
            lines << "movq #{a[2].id}, %rdx"
            lines << "mulxq #{a[3].id}, %rax, %r14"
            lines << "addq %rax, %r13"
            lines << "adcq $$0, %r14"
            lines << "movq #{a[0].id}, %rdx"
            lines << "xorl %ecx, %ecx"
            lines << "mulxq %rdx, %r8, %rax"
            lines << "adcxq %r9, %r9"
            lines << "adoxq %rax, %r9"
            lines << "movq #{a[1].id}, %rdx"
            lines << "mulxq %rdx, %rax, %rcx"
            lines << "adcxq %r10, %r10"
            lines << "adoxq %rax, %r10"
            lines << "adcxq %r11, %r11"
            lines << "adoxq %rcx, %r11"
            lines << "movq #{a[2].id}, %rdx"
            lines << "mulxq %rdx, %rax, %rcx"
            lines << "adcxq %r12, %r12"
            lines << "adoxq %rax, %r12"
            lines << "adcxq %r13, %r13"
            lines << "adoxq %rcx, %r13"
            lines << "movq #{a[3].id}, %rdx"
            lines << "mulxq %rdx, %rax, %r15"
            lines << "adcxq %r14, %r14"
            lines << "adoxq %rax, %r14"
            lines << "movl $$0, %ecx"
            lines << "adcxq %rcx, %r15"
            lines << "adoxq %rcx, %r15"
          %}
        {% elsif operation == "scmul" %}
          {%
            lines << "movl $$121666, %eax"
            lines << "mulq #{a[0].id}"
            lines << "movq %rax, %r8"
            lines << "movq %rdx, %r9"
          %}
          {% for index in 1..3 %}
            {%
              lines << "movl $$121666, %eax"
              lines << "mulq #{a[index].id}"
              lines << "addq %rax, #{product[index].id}"
              lines << "adcq $$0, %rdx"
              lines << "movq %rdx, #{(index == 3 ? "%rcx" : product[index + 1]).id}"
            %}
          {% end %}
          {%
            lines << "movl $$38, %eax"
            lines << "mulq %rcx"
          %}
        {% elsif operation == "wide_scmul" %}
          {%
            lines << "movl $$121666, %edx"
            lines << "mulxq #{a[0].id}, %r8, %r9"
            lines << "mulxq #{a[1].id}, %rax, %r10"
            lines << "addq %rax, %r9"
            lines << "mulxq #{a[2].id}, %rax, %r11"
            lines << "adcq %rax, %r10"
            lines << "mulxq #{a[3].id}, %rax, %rcx"
            lines << "adcq %rax, %r11"
            lines << "adcq $$0, %rcx"
            lines << "movl $$38, %edx"
            lines << "mulxq %rcx, %rax, %rcx"
          %}
        {% elsif operation == "add" || operation == "sub" %}
          {%
            first = operation == "sub" ? "subq" : "addq"
            chain = operation == "sub" ? "sbbq" : "adcq"
          %}
          {% for index in 0..3 %}
            {%
              lines << "movq #{a[index].id}, #{product[index].id}"
              lines << "#{(index == 0 ? first : chain).id} #{b[index].id}, #{product[index].id}"
            %}
          {% end %}
          {%
            lines << "sbbq %rax, %rax"
            lines << "andq $$38, %rax"
            lines << "#{first.id} %rax, %r8"
            lines << "#{chain.id} $$0, %r9"
            lines << "#{chain.id} $$0, %r10"
            lines << "#{chain.id} $$0, %r11"
            lines << "sbbq %rax, %rax"
            lines << "andq $$38, %rax"
            lines << "#{first.id} %rax, %r8"
          %}
        {% elsif operation == "cswap" %}
          {% for index in 0..3 %}
            {%
              lines << "movq #{a[index].id}, %r8"
              lines << "movq #{b[index].id}, %r9"
              lines << "movq %r8, %r10"
              lines << "xorq %r9, %r10"
              lines << "andq #{mask_operand.id}, %r10"
              lines << "xorq %r10, %r8"
              lines << "xorq %r10, %r9"
              lines << "movq %r8, #{a[index].id}"
              lines << "movq %r9, #{b[index].id}"
            %}
          {% end %}
        {% else %}
          {% raise "unknown operation #{operation}" %}
        {% end %}
        {% if operation == "mul" %}
          {%
            lines << "movl $$38, %eax"
            lines << "mulq %r12"
            lines << "addq %rax, %r8"
            lines << "adcq $$0, %rdx"
            lines << "movq %rdx, %rcx"
          %}
          {% for index in 1..3 %}
            {%
              lines << "movl $$38, %eax"
              lines << "mulq #{product[index + 4].id}"
              lines << "addq %rcx, %rax"
              lines << "adcq $$0, %rdx"
              lines << "addq %rax, #{product[index].id}"
              lines << "adcq $$0, %rdx"
              lines << "movq %rdx, %rcx"
            %}
          {% end %}
          {%
            lines << "movl $$38, %eax"
            lines << "mulq %rcx"
          %}
        {% elsif operation == "wide_mul" || operation == "wide_square" %}
          {%
            lines << "movl $$38, %edx"
            lines << "xorl %eax, %eax"
          %}
          {% for index in 0..2 %}
            {%
              lines << "mulxq #{product[index + 4].id}, %rax, %rcx"
              lines << "adcxq %rax, #{product[index].id}"
              lines << "adoxq %rcx, #{product[index + 1].id}"
            %}
          {% end %}
          {%
            lines << "mulxq %r15, %rax, %r12"
            lines << "adcxq %rax, %r11"
            lines << "movl $$0, %ecx"
            lines << "adoxq %rcx, %r12"
            lines << "adcxq %rcx, %r12"
            lines << "mulxq %r12, %rax, %rcx"
          %}
        {% end %}
        {% if operation == "mul" || operation == "wide_mul" || operation == "wide_square" || operation == "scmul" || operation == "wide_scmul" %}
          {%
            lines << "addq %rax, %r8"
            lines << "adcq $$0, %r9"
            lines << "adcq $$0, %r10"
            lines << "adcq $$0, %r11"
            lines << "sbbq %rax, %rax"
            lines << "andq $$38, %rax"
            lines << "addq %rax, %r8"
          %}
        {% end %}
        {% if destination %}
          {% for index in 0..3 %}
            {% lines << "movq #{product[index].id}, #{destination[index].id}" %}
          {% end %}
        {% end %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: {% for pointer, index in pointers %}{% if index > 0 %}, {% end %}"r"({{ pointer }}){% end %}{% if mask %}, "r"({{ mask }}){% end %}
        : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "memory", "flags")
    end

    # One x86-64 field operation (`x86_64_sequence_statement`): *result* =
    # *operation*(*a*, *b*), all three `Limbs` variables.
    macro x86_64_statement(operation, result, a, b)
      ::Amber::Beryl::Crypto::FieldArithmetic::Curve25519SolinasFieldWithAssembly.x86_64_sequence_statement(
        [{ {{ operation }}, {"$0", 0}, {"$1", 0}, {"$2", 0} }],
        [pointerof({{ result }}), pointerof({{ a }}), pointerof({{ b }})])
    end

    # One step of the X25519 ladder on x86-64 in one statement, the steps of
    # `DiffieHellmanOverCurve25519.ladder`: the conditional swap under
    # *mask*, then the step, on the state at *state* (u, x_2, z_2, x_3 and
    # z_3, four words each) with *scratch* (40 words); *wide* picks `mulx`.
    macro x86_64_ladder_step_statement(wide, scratch, state, mask)
      {%
        multiply = wide ? "wide_mul" : "mul"
        square = wide ? "wide_square" : "mul"
        scalar_multiply = wide ? "wide_scmul" : "scmul"
        u = {"$1", 0}
        x2 = {"$1", 32}
        z2 = {"$1", 64}
        x3 = {"$1", 96}
        z3 = {"$1", 128}
        slot = (0..9).map { |index| {"$0", 32 * index} }
        # The operations of `DiffieHellmanOverCurve25519.ladder`, ordered
        # so that independent ones sit next to each other: A, B, C and D;
        # then DA, CB, AA and BB; then DA ± CB and E = AA - BB; then the
        # rest. Each value is what the ladder computes, so the result is.
        steps = [
          {"cswap", nil, x2, x3},
          {"cswap", nil, z2, z3},
          {"add", slot[0], x2, z2},
          {"sub", slot[2], x2, z2},
          {"add", slot[5], x3, z3},
          {"sub", slot[6], x3, z3},
          {multiply, slot[7], slot[6], slot[0]},
          {multiply, slot[8], slot[5], slot[2]},
          {square, slot[1], slot[0], slot[0]},
          {square, slot[3], slot[2], slot[2]},
          {"add", slot[9], slot[7], slot[8]},
          {"sub", slot[0], slot[7], slot[8]},
          {"sub", slot[4], slot[1], slot[3]},
          {square, x3, slot[9], slot[9]},
          {square, slot[0], slot[0], slot[0]},
          {multiply, x2, slot[1], slot[3]},
          {scalar_multiply, slot[9], slot[4], slot[4]},
          {multiply, z3, u, slot[0]},
          {"add", slot[9], slot[3], slot[9]},
          {multiply, z2, slot[4], slot[9]},
        ]
      %}
      ::Amber::Beryl::Crypto::FieldArithmetic::Curve25519SolinasFieldWithAssembly.x86_64_sequence_statement({{ steps }}, [{{ scratch }}, {{ state }}], {{ mask }})
    end

    # The swap that ends the ladder, on x86-64: (x_2, z_2) and (x_3, z_3)
    # of the state at *state* exchanged under *mask*.
    macro x86_64_ladder_swap_statement(state, mask)
      ::Amber::Beryl::Crypto::FieldArithmetic::Curve25519SolinasFieldWithAssembly.x86_64_sequence_statement(
        [{"cswap", nil, {"$0", 32}, {"$0", 96}}, {"cswap", nil, {"$0", 64}, {"$0", 128}}], [{{ state }}], {{ mask }})
    end

    # One AArch64 statement on registers: $0 to $3 the result, $4 to $12
    # scratch, then the words of a ($13 to $16) and of b ($17 to $20).
    # *operation* is one of `mul`, `square` (the cross products once,
    # doubled by `extr`), `scmul` (121666·a), `add` and `sub`. A product in
    # $0 to $7 is folded as on x86-64, with 38 in $12; carries become masks
    # with `csel`.
    macro aarch64_statement(operation, a, b)
      {%
        lines = [] of StringLiteral
        a_words = (13..16).map { |index| "$#{index}" }
        b_words = (17..20).map { |index| "$#{index}" }
        p = (0..7).map { |index| "$#{index}" }
        s = (8..11).map { |index| "$#{index}" }
      %}
      {% if operation == "mul" %}
        {%
          lines << "mul #{p[0].id}, #{a_words[0].id}, #{b_words[0].id}"
          lines << "umulh #{p[1].id}, #{a_words[0].id}, #{b_words[0].id}"
          lines << "mul #{s[0].id}, #{a_words[0].id}, #{b_words[1].id}"
          lines << "umulh #{p[2].id}, #{a_words[0].id}, #{b_words[1].id}"
          lines << "mul #{s[1].id}, #{a_words[0].id}, #{b_words[2].id}"
          lines << "umulh #{p[3].id}, #{a_words[0].id}, #{b_words[2].id}"
          lines << "mul #{s[2].id}, #{a_words[0].id}, #{b_words[3].id}"
          lines << "umulh #{p[4].id}, #{a_words[0].id}, #{b_words[3].id}"
          lines << "adds #{p[1].id}, #{p[1].id}, #{s[0].id}"
          lines << "adcs #{p[2].id}, #{p[2].id}, #{s[1].id}"
          lines << "adcs #{p[3].id}, #{p[3].id}, #{s[2].id}"
          lines << "adc #{p[4].id}, #{p[4].id}, xzr"
        %}
        {% for row in 1..3 %}
          {% for column in 0..3 %}
            {% lines << "mul #{s[column].id}, #{a_words[row].id}, #{b_words[column].id}" %}
          {% end %}
          {%
            lines << "adds #{p[row].id}, #{p[row].id}, #{s[0].id}"
            lines << "adcs #{p[row + 1].id}, #{p[row + 1].id}, #{s[1].id}"
            lines << "adcs #{p[row + 2].id}, #{p[row + 2].id}, #{s[2].id}"
            lines << "adcs #{p[row + 3].id}, #{p[row + 3].id}, #{s[3].id}"
            lines << "adc #{p[row + 4].id}, xzr, xzr"
          %}
          {% for column in 0..3 %}
            {% lines << "umulh #{s[column].id}, #{a_words[row].id}, #{b_words[column].id}" %}
          {% end %}
          {%
            lines << "adds #{p[row + 1].id}, #{p[row + 1].id}, #{s[0].id}"
            lines << "adcs #{p[row + 2].id}, #{p[row + 2].id}, #{s[1].id}"
            lines << "adcs #{p[row + 3].id}, #{p[row + 3].id}, #{s[2].id}"
            lines << "adc #{p[row + 4].id}, #{p[row + 4].id}, #{s[3].id}"
          %}
        {% end %}
      {% elsif operation == "square" %}
        {%
          lines << "mul #{p[1].id}, #{a_words[0].id}, #{a_words[1].id}"
          lines << "umulh #{p[2].id}, #{a_words[0].id}, #{a_words[1].id}"
          lines << "mul #{s[0].id}, #{a_words[0].id}, #{a_words[2].id}"
          lines << "umulh #{p[3].id}, #{a_words[0].id}, #{a_words[2].id}"
          lines << "mul #{s[1].id}, #{a_words[0].id}, #{a_words[3].id}"
          lines << "umulh #{p[4].id}, #{a_words[0].id}, #{a_words[3].id}"
          lines << "adds #{p[2].id}, #{p[2].id}, #{s[0].id}"
          lines << "adcs #{p[3].id}, #{p[3].id}, #{s[1].id}"
          lines << "adc #{p[4].id}, #{p[4].id}, xzr"
          lines << "mul #{s[0].id}, #{a_words[1].id}, #{a_words[2].id}"
          lines << "umulh #{s[1].id}, #{a_words[1].id}, #{a_words[2].id}"
          lines << "mul #{s[2].id}, #{a_words[1].id}, #{a_words[3].id}"
          lines << "umulh #{p[5].id}, #{a_words[1].id}, #{a_words[3].id}"
          lines << "adds #{p[3].id}, #{p[3].id}, #{s[0].id}"
          lines << "adcs #{p[4].id}, #{p[4].id}, #{s[2].id}"
          lines << "adc #{p[5].id}, #{p[5].id}, xzr"
          lines << "mul #{s[0].id}, #{a_words[2].id}, #{a_words[3].id}"
          lines << "umulh #{p[6].id}, #{a_words[2].id}, #{a_words[3].id}"
          lines << "adds #{p[4].id}, #{p[4].id}, #{s[1].id}"
          lines << "adcs #{p[5].id}, #{p[5].id}, #{s[0].id}"
          lines << "adc #{p[6].id}, #{p[6].id}, xzr"
          lines << "lsr #{p[7].id}, #{p[6].id}, #63"
          lines << "extr #{p[6].id}, #{p[6].id}, #{p[5].id}, #63"
          lines << "extr #{p[5].id}, #{p[5].id}, #{p[4].id}, #63"
          lines << "extr #{p[4].id}, #{p[4].id}, #{p[3].id}, #63"
          lines << "extr #{p[3].id}, #{p[3].id}, #{p[2].id}, #63"
          lines << "extr #{p[2].id}, #{p[2].id}, #{p[1].id}, #63"
          lines << "lsl #{p[1].id}, #{p[1].id}, #1"
          lines << "mul #{p[0].id}, #{a_words[0].id}, #{a_words[0].id}"
          lines << "umulh #{s[0].id}, #{a_words[0].id}, #{a_words[0].id}"
          lines << "mul #{s[1].id}, #{a_words[1].id}, #{a_words[1].id}"
          lines << "umulh #{s[2].id}, #{a_words[1].id}, #{a_words[1].id}"
          lines << "adds #{p[1].id}, #{p[1].id}, #{s[0].id}"
          lines << "adcs #{p[2].id}, #{p[2].id}, #{s[1].id}"
          lines << "adcs #{p[3].id}, #{p[3].id}, #{s[2].id}"
          lines << "mul #{s[0].id}, #{a_words[2].id}, #{a_words[2].id}"
          lines << "umulh #{s[1].id}, #{a_words[2].id}, #{a_words[2].id}"
          lines << "mul #{s[2].id}, #{a_words[3].id}, #{a_words[3].id}"
          lines << "umulh #{s[3].id}, #{a_words[3].id}, #{a_words[3].id}"
          lines << "adcs #{p[4].id}, #{p[4].id}, #{s[0].id}"
          lines << "adcs #{p[5].id}, #{p[5].id}, #{s[1].id}"
          lines << "adcs #{p[6].id}, #{p[6].id}, #{s[2].id}"
          lines << "adc #{p[7].id}, #{p[7].id}, #{s[3].id}"
        %}
      {% elsif operation == "scmul" %}
        {%
          lines << "movz $12, #0xdb42"
          lines << "movk $12, #0x1, lsl #16"
        %}
        {% for index in 0..3 %}
          {%
            lines << "mul #{p[index].id}, #{a_words[index].id}, $12"
            lines << "umulh #{s[index].id}, #{a_words[index].id}, $12"
          %}
        {% end %}
        {%
          lines << "adds #{p[1].id}, #{p[1].id}, #{s[0].id}"
          lines << "adcs #{p[2].id}, #{p[2].id}, #{s[1].id}"
          lines << "adcs #{p[3].id}, #{p[3].id}, #{s[2].id}"
          lines << "adc #{s[3].id}, #{s[3].id}, xzr"
          lines << "mov $12, #38"
          lines << "mul #{s[3].id}, #{s[3].id}, $12"
          lines << "adds #{p[0].id}, #{p[0].id}, #{s[3].id}"
          lines << "adcs #{p[1].id}, #{p[1].id}, xzr"
          lines << "adcs #{p[2].id}, #{p[2].id}, xzr"
          lines << "adcs #{p[3].id}, #{p[3].id}, xzr"
          lines << "csel #{s[0].id}, $12, xzr, cs"
          lines << "add #{p[0].id}, #{p[0].id}, #{s[0].id}"
        %}
      {% elsif operation == "add" %}
        {%
          lines << "mov $12, #38"
          lines << "adds #{p[0].id}, #{a_words[0].id}, #{b_words[0].id}"
          lines << "adcs #{p[1].id}, #{a_words[1].id}, #{b_words[1].id}"
          lines << "adcs #{p[2].id}, #{a_words[2].id}, #{b_words[2].id}"
          lines << "adcs #{p[3].id}, #{a_words[3].id}, #{b_words[3].id}"
          lines << "csel #{s[0].id}, $12, xzr, cs"
          lines << "adds #{p[0].id}, #{p[0].id}, #{s[0].id}"
          lines << "adcs #{p[1].id}, #{p[1].id}, xzr"
          lines << "adcs #{p[2].id}, #{p[2].id}, xzr"
          lines << "adcs #{p[3].id}, #{p[3].id}, xzr"
          lines << "csel #{s[0].id}, $12, xzr, cs"
          lines << "add #{p[0].id}, #{p[0].id}, #{s[0].id}"
        %}
      {% elsif operation == "sub" %}
        {%
          lines << "mov $12, #38"
          lines << "subs #{p[0].id}, #{a_words[0].id}, #{b_words[0].id}"
          lines << "sbcs #{p[1].id}, #{a_words[1].id}, #{b_words[1].id}"
          lines << "sbcs #{p[2].id}, #{a_words[2].id}, #{b_words[2].id}"
          lines << "sbcs #{p[3].id}, #{a_words[3].id}, #{b_words[3].id}"
          lines << "csel #{s[0].id}, xzr, $12, cs"
          lines << "subs #{p[0].id}, #{p[0].id}, #{s[0].id}"
          lines << "sbcs #{p[1].id}, #{p[1].id}, xzr"
          lines << "sbcs #{p[2].id}, #{p[2].id}, xzr"
          lines << "sbcs #{p[3].id}, #{p[3].id}, xzr"
          lines << "csel #{s[0].id}, xzr, $12, cs"
          lines << "sub #{p[0].id}, #{p[0].id}, #{s[0].id}"
        %}
      {% else %}
        {% raise "unknown operation #{operation}" %}
      {% end %}
      {% if operation == "mul" || operation == "square" %}
        {% lines << "mov $12, #38" %}
        {% for index in 0..3 %}
          {%
            lines << "mul #{s[index].id}, #{p[index + 4].id}, $12"
            lines << "umulh #{p[index + 4].id}, #{p[index + 4].id}, $12"
          %}
        {% end %}
        {%
          lines << "adds #{p[0].id}, #{p[0].id}, #{s[0].id}"
          lines << "adcs #{p[1].id}, #{p[1].id}, #{s[1].id}"
          lines << "adcs #{p[2].id}, #{p[2].id}, #{s[2].id}"
          lines << "adcs #{p[3].id}, #{p[3].id}, #{s[3].id}"
          lines << "adc #{p[7].id}, #{p[7].id}, xzr"
          lines << "adds #{p[1].id}, #{p[1].id}, #{p[4].id}"
          lines << "adcs #{p[2].id}, #{p[2].id}, #{p[5].id}"
          lines << "adcs #{p[3].id}, #{p[3].id}, #{p[6].id}"
          lines << "adc #{p[7].id}, #{p[7].id}, xzr"
          lines << "mul #{s[0].id}, #{p[7].id}, $12"
          lines << "adds #{p[0].id}, #{p[0].id}, #{s[0].id}"
          lines << "adcs #{p[1].id}, #{p[1].id}, xzr"
          lines << "adcs #{p[2].id}, #{p[2].id}, xzr"
          lines << "adcs #{p[3].id}, #{p[3].id}, xzr"
          lines << "csel #{s[0].id}, $12, xzr, cs"
          lines << "add #{p[0].id}, #{p[0].id}, #{s[0].id}"
        %}
      {% end %}
      result_0 = result_1 = result_2 = result_3 = 0_u64
      scratch_4 = scratch_5 = scratch_6 = scratch_7 = scratch_8 = scratch_9 = scratch_10 = scratch_11 = scratch_12 = 0_u64
      asm({{ lines.join("\n") }} : "=&r"(result_0), "=&r"(result_1), "=&r"(result_2), "=&r"(result_3),
                                   "=&r"(scratch_4), "=&r"(scratch_5), "=&r"(scratch_6), "=&r"(scratch_7),
                                   "=&r"(scratch_8), "=&r"(scratch_9), "=&r"(scratch_10), "=&r"(scratch_11), "=&r"(scratch_12)
                                 : "r"({{ a }}.unsafe_fetch(0)), "r"({{ a }}.unsafe_fetch(1)), "r"({{ a }}.unsafe_fetch(2)), "r"({{ a }}.unsafe_fetch(3)),
                                   "r"({{ b }}.unsafe_fetch(0)), "r"({{ b }}.unsafe_fetch(1)), "r"({{ b }}.unsafe_fetch(2)), "r"({{ b }}.unsafe_fetch(3))
                                 : "cc")
      StaticArray[result_0, result_1, result_2, result_3]
    end

    {% if flag?(:aarch64) %}
      # `mul`, `umulh` and `adds`/`adcs` on registers.
      module AArch64
        alias Limbs = StaticArray(UInt64, 4)

        @[AlwaysInline]
        def self.mul(a : Limbs, b : Limbs) : Limbs
          Curve25519SolinasFieldWithAssembly.aarch64_statement("mul", a, b)
        end

        @[AlwaysInline]
        def self.square(a : Limbs) : Limbs
          Curve25519SolinasFieldWithAssembly.aarch64_statement("square", a, a)
        end

        @[AlwaysInline]
        def self.add(a : Limbs, b : Limbs) : Limbs
          Curve25519SolinasFieldWithAssembly.aarch64_statement("add", a, b)
        end

        @[AlwaysInline]
        def self.sub(a : Limbs, b : Limbs) : Limbs
          Curve25519SolinasFieldWithAssembly.aarch64_statement("sub", a, b)
        end

        @[AlwaysInline]
        def self.scmul_121666(a : Limbs) : Limbs
          Curve25519SolinasFieldWithAssembly.aarch64_statement("scmul", a, a)
        end
      end
    {% end %}

    {% if flag?(:x86_64) %}
      {% for module_name, operations in {X86WithMultiply: {"mul", "mul", "scmul"}, X86WithWideMultiply: {"wide_mul", "wide_square", "wide_scmul"}} %}
        # x86-64 with {{ module_name == :X86WithMultiply ? "`mulq`: every x86-64 processor".id : "`mulx`, `adcx` and `adox` (BMI2 and ADX)".id }}.
        module {{ module_name.id }}
          alias Limbs = StaticArray(UInt64, 4)

          def self.mul(a : Limbs, b : Limbs) : Limbs
            result = uninitialized Limbs
            Curve25519SolinasFieldWithAssembly.x86_64_statement({{ operations[0] }}, result, a, b)
            result
          end

          def self.square(a : Limbs) : Limbs
            result = uninitialized Limbs
            Curve25519SolinasFieldWithAssembly.x86_64_statement({{ operations[1] }}, result, a, a)
            result
          end

          def self.add(a : Limbs, b : Limbs) : Limbs
            result = uninitialized Limbs
            Curve25519SolinasFieldWithAssembly.x86_64_statement("add", result, a, b)
            result
          end

          def self.sub(a : Limbs, b : Limbs) : Limbs
            result = uninitialized Limbs
            Curve25519SolinasFieldWithAssembly.x86_64_statement("sub", result, a, b)
            result
          end

          def self.scmul_121666(a : Limbs) : Limbs
            result = uninitialized Limbs
            Curve25519SolinasFieldWithAssembly.x86_64_statement({{ operations[2] }}, result, a, a)
            result
          end
        end
      {% end %}
    {% end %}
  end
end
