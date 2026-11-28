module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # Montgomery multiplication and squaring for RSA in x86-64 assembly, with
  # `mulx` (BMI2) and `adcx` and `adox` (ADX): the twin of the AArch64
  # `MontgomeryMultiplicationInAssembly`, one copy for each word count
  # `MontgomeryArithmetic` specializes, taken where
  # `ProcessorFeatures::HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS` says the
  # processor has them. Each computes what `MontgomeryArithmetic.multiply`
  # computes: a·b + M·m for the unique M below R that makes it divisible by
  # R, divided by R, less m once when that is not below m. The result is the
  # same integer however the product and the reduction are ordered, and
  # spec/beryl/crypto/v1/montgomery_arithmetic_spec.cr compares each with
  # the Crystal multiplication.
  #
  # The method is the AArch64 kernel's (separated operand scanning, in
  # strips of eight words), arranged for the x86-64 instructions as Intel
  # describes them in "New Instructions Supporting Large Integer Arithmetic
  # on Intel Architecture Processors" (Ozturk, Guilford, Gopal, Feghali,
  # 2012): `mulx` multiplies without touching the flags, and `adcx` and
  # `adox` add with carry through two different flags (CF and OF), so the
  # low halves of a row of word products go up one carry chain and the high
  # halves up the other, both at once.
  #
  # A strip holds eight words x of one factor (read from memory by `mulx`)
  # against each word y of a run of the other (in rdx, one per row). A row
  # adds x·y to a window of nine registers, renamed from row to row as the
  # window moves up a word: `mulx` gives x_i·y as (lo, hi), `adcx` adds lo
  # to window word i and `adox` adds hi to word i + 1; the last high half
  # lands in the ninth register, the new top word, and both carries end in
  # it. The window holds only the strip's own sum; the word leaving it is
  # added to T's word at that place (`adcx` from memory), and the carry of
  # that addition enters the next row's first `adcx`. The window stays below
  # 2^576, so its top word never overflows, and when a strip of the product
  # ends, its last eight words (with the last carry) go to a part of T that
  # no earlier strip reached.
  #
  # - Product a·b: strip c takes x = a[8c..8c+7] and y = b, into T from word
  #   8c, in a loop over the strips (a is first copied beside T, so that one
  #   pointer reaches both). Squaring: strip c takes y = a[8c..n), its first
  #   eight rows using only the words of x below the row (the products
  #   a_i·a_j with i < j), unrolled; one pass then doubles T (`adcx` of each
  #   word to itself) and adds each a_i² (`adox`), the two chains at once.
  # - Reduction, eight words at a time, in a loop over the blocks:
  #   T[8q..8q+7] is loaded into the window and, row by row,
  #   u_j = T[8q+j]·(-m^-1) mod 2^64 is formed (`mulx`, which leaves the
  #   flags alone) and u_j·m[0..7] added, which clears that word; the eight
  #   u_j, stored, are then a strip against y = m[8..n). That strip ends
  #   inside the top half of T, so its last nine words are added to T there
  #   (the window by one chain, T by the other); the two carries out, at
  #   word 8q + n + 9, are kept in the scratch and added at the next block's
  #   end, eight words higher, which lies above every word a later block
  #   reads to form its u.
  #
  # Registers: the window is rax, rbx, rcx, rsi, rdi, rbp, r8, r9 and r10;
  # r11 and r12 take the halves of each product; rdx is the multiplier
  # `mulx` reads; r13 is the moving pointer (to the strip or the block); r14
  # counts the strips or the blocks; and $0, which arrives pointing at the
  # six operand words (the result, a, b, m, -m^-1 mod 2^64 and the scratch),
  # holds b during the product of a multiplication, a during a squaring's,
  # and the scratch during the reduction.
  #
  # The scratch (`SCRATCH_WORD_COUNT_PER_WORD` words per word of the
  # modulus, plus `SCRATCH_EXTRA_WORD_COUNT`), in words: 0 the result
  # pointer, 1 -m^-1 mod 2^64, 2 the reduction's carry, 3 unused, then the
  # modulus (n words), T (2n + 2), the copy of a (n) and the reduction's
  # u_j (n). The result may be a or b: it is written last.
  #
  # Constant time: the two loops (over the strips of a·b, and over the
  # reduction blocks) count down from constants; there is no other branch
  # and no address computed from data, and `cmovc` keeps or drops the final
  # subtraction. `mulx`, `adcx`, `adox` and `cmovc` take the same time
  # whatever their operands hold. `scripts/check_secret_flow.rb` checks the
  # text.
  module MontgomeryMultiplicationWithTwoCarryChains
    {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
      AVAILABLE = true
    {% else %}
      AVAILABLE = false
    {% end %}

    SCRATCH_WORD_COUNT_PER_WORD = 5
    SCRATCH_EXTRA_WORD_COUNT    = 6

    # The text of a Montgomery multiplication (or, with *square*, a
    # squaring) of *word_count*-word numbers, a multiple of 8, as described
    # above; *parameters* points at the six operand words.
    #
    # For 16 and 24 words the loops are written out (the strips of a·b, and
    # the reduction blocks), which frees r14 to point at the modulus and a
    # register to point at a: those copies are not made, and the first strip
    # stores its words without adding them to T, so T is not cleared first.
    macro strip_statement(word_count, square, parameters)
      {%
        n = word_count
        is_unrolled = n <= 24
        initial_window = %w(rax rbx rcx rsi rdi rbp r8 r9 r10)
        modulus_offset = 32
        t_offset = 8 * (4 + n)
        a_offset = t_offset + 8 * (2 * n + 2)
        u_offset = a_offset + 8 * n
        lines = [] of StringLiteral
        lines << "mov 40($0), %r13"
        lines << "mov 0($0), %r11"
        lines << "mov %r11, 0(%r13)"
        lines << "mov 32($0), %r11"
        lines << "mov %r11, 8(%r13)"
        lines << "mov 24($0), %r11"
      %}
      # Set up the scratch: the result pointer, -m^-1, then where the loops
      # need them the modulus, the copy of a and T's words that are added
      # before they are written.
      {% if is_unrolled %}
        {% lines << "mov %r11, 24(%r13)" %}
      {% else %}
        {% for k in 0...n %}
          {% lines << "mov #{8 * k}(%r11), %r12" %}
          {% lines << "mov %r12, #{modulus_offset + 8 * k}(%r13)" %}
        {% end %}
      {% end %}
      {% if !square && !is_unrolled %}
        {% lines << "mov 8($0), %r11" %}
        {% for k in 0...n %}
          {% lines << "mov #{8 * k}(%r11), %r12" %}
          {% lines << "mov %r12, #{a_offset + 8 * k}(%r13)" %}
        {% end %}
      {% end %}
      {% lines << "mov $$0, %r12" %}
      {% lines << "mov %r12, 32(%r13)" if is_unrolled %}
      {% if !square && !is_unrolled %}
        {% for k in 0...n %}
          {% lines << "mov %r12, #{t_offset + 8 * k}(%r13)" %}
        {% end %}
      {% end %}
      {% lines << "mov %r12, #{t_offset + 16 * n}(%r13)" %}

      {% if square %}
        {%
          lines << "mov 8($0), $0"
          lines << "mov $$0, %r14"
          zero = "%r14"
        %}
        {% for chunk in 0...(n // 8) %}
          {% window = initial_window %}
          {% for index in 0...8 %}
            {% lines << "xor %#{window[index].id}, %#{window[index].id}" %}
          {% end %}
          {% for row in 0...(n - 8 * chunk) %}
            {% count = row < 8 ? row : 8 %}
            {% t_operand = "#{t_offset + 8 * (16 * chunk + row)}(%r13)" %}
            {% if count == 8 %}
              {% lines << "mov #{8 * (8 * chunk + row)}($0), %rdx" %}
              {% lines << "adox #{t_operand.id}, %#{window[0].id}" if chunk > 0 %}
              {% for i in 0...7 %}
                {% lines << "mulx #{8 * (8 * chunk + i)}($0), %r11, %r12" %}
                {% lines << "adcx %r11, %#{window[i].id}" %}
                {% lines << "adox %r12, %#{window[i + 1].id}" %}
              {% end %}
              {%
                lines << "mulx #{8 * (8 * chunk + 7)}($0), %r11, %#{window[8].id}"
                lines << "adcx %r11, %#{window[7].id}"
                lines << "mov $$0, %r11" if zero == "%r11"
                lines << "adox #{zero.id}, %#{window[8].id}"
                lines << "adcx #{zero.id}, %#{window[8].id}"
              %}
            {% else %}
              {% lines << "mov $$0, %#{window[8].id}" %}
              {% if count > 0 %}
                {% lines << "mov #{8 * (8 * chunk + row)}($0), %rdx" %}
                {% lines << "adox #{t_operand.id}, %#{window[0].id}" if chunk > 0 %}
                {% for i in 0...count %}
                  {% lines << "mulx #{8 * (8 * chunk + i)}($0), %r11, %r12" %}
                  {% lines << "adcx %r11, %#{window[i].id}" %}
                  {% lines << "adox %r12, %#{window[i + 1].id}" %}
                {% end %}
                {% lines << "adcx %r14, %#{window[count].id}" %}
                {% lines << "adox %r14, %#{window[count + 1].id}" %}
                {% lines << "adcx %r14, %#{window[count + 1].id}" %}
              {% end %}
            {% end %}
            {% if chunk > 0 && count == 0 %}
              {% lines << "adcx #{t_operand.id}, %#{window[0].id}" %}
            {% end %}
            {% lines << "mov %#{window[0].id}, #{t_operand.id}" %}
            {% window = window[1..-1] + [window[0]] %}
          {% end %}
          {% lines << "mov $$0, %r11" %}
          {% for index in 0...8 %}
            {% lines << "adcx %r11, %#{window[index].id}" %}
            {% lines << "mov %#{window[index].id}, #{t_offset + 8 * (8 * chunk + n + index)}(%r13)" %}
          {% end %}
        {% end %}
        # Double T and add the squares a_i² on the diagonal.
        {% lines << "xor %r11, %r11" %}
        {% for k in 0...n %}
          {%
            lines << "mov #{8 * k}($0), %rdx"
            lines << "mulx %rdx, %r11, %r12"
            lines << "mov #{t_offset + 16 * k}(%r13), %rax"
            lines << "mov #{t_offset + 16 * k + 8}(%r13), %rbx"
            lines << "adcx %rax, %rax"
            lines << "adcx %rbx, %rbx"
            lines << "adox %r11, %rax"
            lines << "adox %r12, %rbx"
            lines << "mov %rax, #{t_offset + 16 * k}(%r13)"
            lines << "mov %rbx, #{t_offset + 16 * k + 8}(%r13)"
          %}
        {% end %}
      {% elsif is_unrolled %}
        {%
          zero = "32(%r13)"
          lines << "mov 16($0), %r14"
          lines << "mov 8($0), $0"
        %}
        {% for chunk in 0...(n // 8) %}
          {% window = initial_window %}
          {% for index in 0...8 %}
            {% lines << "xor %#{window[index].id}, %#{window[index].id}" %}
          {% end %}
          {% for row in 0...n %}
            {% t_operand = "#{t_offset + 8 * (8 * chunk + row)}(%r13)" %}
            {% lines << "mov #{8 * row}(%r14), %rdx" %}
            {% lines << "adox #{t_operand.id}, %#{window[0].id}" if chunk > 0 %}
            {% for i in 0...7 %}
              {% lines << "mulx #{8 * (8 * chunk + i)}($0), %r11, %r12" %}
              {% lines << "adcx %r11, %#{window[i].id}" %}
              {% lines << "adox %r12, %#{window[i + 1].id}" %}
            {% end %}
            {%
              lines << "mulx #{8 * (8 * chunk + 7)}($0), %r11, %#{window[8].id}"
              lines << "adcx %r11, %#{window[7].id}"
              lines << "mov $$0, %r11" if zero == "%r11"
              lines << "adox #{zero.id}, %#{window[8].id}"
              lines << "adcx #{zero.id}, %#{window[8].id}"
            %}
            {% lines << "mov %#{window[0].id}, #{t_operand.id}" %}
            {% window = window[1..-1] + [window[0]] %}
          {% end %}
          {% lines << "mov $$0, %r11" %}
          {% for index in 0...8 %}
            {% lines << "adcx %r11, %#{window[index].id}" %}
            {% lines << "mov %#{window[index].id}, #{t_offset + 8 * (8 * chunk + n + index)}(%r13)" %}
          {% end %}
        {% end %}
      {% else %}
        {% zero = "%r11" %}
        {% lines << "mov 16($0), $0" %}
        {% lines << "mov $$#{n // 8}, %r14" %}
        {% lines << "1:" %}
        {% window = initial_window %}
        {% for index in 0...8 %}
          {% lines << "xor %#{window[index].id}, %#{window[index].id}" %}
        {% end %}
        {% for row in 0...n %}
          {% t_operand = "#{t_offset + 8 * row}(%r13)" %}
          {% lines << "mov #{8 * row}($0), %rdx" %}
          {% lines << "adox #{t_operand.id}, %#{window[0].id}" %}
          {% for i in 0...7 %}
            {% lines << "mulx #{a_offset + 8 * i}(%r13), %r11, %r12" %}
            {% lines << "adcx %r11, %#{window[i].id}" %}
            {% lines << "adox %r12, %#{window[i + 1].id}" %}
          {% end %}
          {%
            lines << "mulx #{a_offset + 56}(%r13), %r11, %#{window[8].id}"
            lines << "adcx %r11, %#{window[7].id}"
            lines << "mov $$0, %r11" if zero == "%r11"
            lines << "adox #{zero.id}, %#{window[8].id}"
            lines << "adcx #{zero.id}, %#{window[8].id}"
            lines << "mov %#{window[0].id}, #{t_operand.id}"
          %}
          {% window = window[1..-1] + [window[0]] %}
        {% end %}
        {% lines << "mov $$0, %r11" %}
        {% for index in 0...8 %}
          {% lines << "adcx %r11, %#{window[index].id}" %}
          {% lines << "mov %#{window[index].id}, #{t_offset + 8 * (n + index)}(%r13)" %}
        {% end %}
        {%
          lines << "lea 64(%r13), %r13"
          lines << "dec %r14"
          lines << "jnz 1b"
          lines << "lea -#{8 * n}(%r13), %r13"
        %}
      {% end %}

      # The reduction, eight words a block. Written out, r13 holds the
      # scratch and r14 points at the modulus; as a loop, $0 holds the
      # scratch (with the copy of the modulus) and r13 moves up a block at a
      # time.
      {% if is_unrolled %}
        {%
          zero = "32(%r13)"
          lines << "mov 24(%r13), %r14"
          scratch_base = "%r13"
          block_count = n // 8
          m_operands = (0...n).to_a.map { |k| "#{8 * k}(%r14)" }
        %}
      {% else %}
        {%
          zero = "%r11"
          lines << "mov %r13, $0"
          scratch_base = "$0"
          block_count = 1
          m_operands = (0...n).to_a.map { |k| "#{modulus_offset + 8 * k}($0)" }
        %}
      {% end %}
      {%
        lines << "mov $$0, %r11"
        lines << "mov %r11, 16(#{scratch_base.id})"
      %}
      {% if !is_unrolled %}
        {%
          lines << "mov $$#{n // 8}, %r14"
          lines << "1:"
        %}
      {% end %}
      {% for block in 0...block_count %}
        {%
          t_base = is_unrolled ? t_offset + 64 * block : t_offset
          lines << "xor %r11, %r11"
          window = initial_window
        %}
        {% for index in 0...8 %}
          {% lines << "mov #{t_base + 8 * index}(%r13), %#{window[index].id}" %}
        {% end %}
        {% for j in 0...8 %}
          {%
            lines << "mov %#{window[0].id}, %rdx"
            lines << "mulx 8(#{scratch_base.id}), %rdx, %r12"
            lines << "mov %rdx, #{u_offset + 8 * j}(%r13)"
          %}
          {% for i in 0...7 %}
            {% lines << "mulx #{m_operands[i].id}, %r11, %r12" %}
            {% lines << "adcx %r11, %#{window[i].id}" %}
            {% lines << "adox %r12, %#{window[i + 1].id}" %}
          {% end %}
          {%
            lines << "mulx #{m_operands[7].id}, %r11, %#{window[8].id}"
            lines << "adcx %r11, %#{window[7].id}"
            lines << "mov $$0, %r11" if zero == "%r11"
            lines << "adox #{zero.id}, %#{window[8].id}"
            lines << "adcx #{zero.id}, %#{window[8].id}"
          %}
          {% window = window[1..-1] + [window[0]] %}
        {% end %}
        {% for row in 0...(n - 8) %}
          {% t_operand = "#{t_base + 8 * (8 + row)}(%r13)" %}
          {% lines << "mov #{m_operands[8 + row].id}, %rdx" %}
          {% lines << "adox #{t_operand.id}, %#{window[0].id}" %}
          {% for i in 0...7 %}
            {% lines << "mulx #{u_offset + 8 * i}(%r13), %r11, %r12" %}
            {% lines << "adcx %r11, %#{window[i].id}" %}
            {% lines << "adox %r12, %#{window[i + 1].id}" %}
          {% end %}
          {%
            lines << "mulx #{u_offset + 56}(%r13), %r11, %#{window[8].id}"
            lines << "adcx %r11, %#{window[7].id}"
            lines << "mov $$0, %r11" if zero == "%r11"
            lines << "adox #{zero.id}, %#{window[8].id}"
            lines << "adcx #{zero.id}, %#{window[8].id}"
            lines << "mov %#{window[0].id}, #{t_operand.id}"
          %}
          {% window = window[1..-1] + [window[0]] %}
        {% end %}
        {%
          lines << "mov $$0, %r11"
          lines << "mov $$0, %#{window[8].id}"
        %}
        {% for index in 0...9 %}
          {% lines << (index == 1 ? "adcx 16(#{scratch_base.id}), %#{window[1].id}" : "adcx %r11, %#{window[index].id}") %}
          {% lines << "adox #{t_base + 8 * (n + index)}(%r13), %#{window[index].id}" %}
          {% lines << "mov %#{window[index].id}, #{t_base + 8 * (n + index)}(%r13)" %}
        {% end %}
        {%
          lines << "mov $$0, %r12"
          lines << "adcx %r11, %r12"
          lines << "adox %r11, %r12"
          lines << "mov %r12, 16(#{scratch_base.id})"
        %}
      {% end %}
      {% if !is_unrolled %}
        {%
          lines << "lea 64(%r13), %r13"
          lines << "dec %r14"
          lines << "jnz 1b"
        %}
      {% end %}
      # T[n..2n] less m into the result; when that borrows, T[n..2n] instead.
      {% lines << "mov 0(#{scratch_base.id}), %rbx" %}
      {% for k in 0...n %}
        {% lines << "mov #{t_offset + 8 * (n + k)}(#{scratch_base.id}), %rax" %}
        {% lines << "#{(k == 0 ? "sub" : "sbb").id} #{m_operands[k].id}, %rax" %}
        {% lines << "mov %rax, #{8 * k}(%rbx)" %}
      {% end %}
      {% lines << "mov #{t_offset + 16 * n}(#{scratch_base.id}), %rax" %}
      {% lines << "sbb $$0, %rax" %}
      {% for k in 0...n %}
        {% lines << "mov #{8 * k}(%rbx), %rax" %}
        {% lines << "cmovc #{t_offset + 8 * (n + k)}(#{scratch_base.id}), %rax" %}
        {% lines << "mov %rax, #{8 * k}(%rbx)" %}
      {% end %}
      %finished = 0_u64
      asm({{ lines.join("\n") }}
        : "=r"(%finished) : "0"({{ parameters }})
        : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "memory", "flags")
    end

    # The text that copies entry $0[2] (below 32, secret) of a table of 32
    # entries of *word_count* words at $0[1] into $0[0], with AVX2: every
    # entry is read, ANDed with the mask of lanes where the entry's number
    # (counted up in ymm1) equals the index (`vpcmpeqq`), and ORed in, 32
    # words (eight registers) at a time.
    macro select_entry_with_vectors_statement(word_count, parameters)
      {%
        lines = [] of StringLiteral
        lines << "mov 0($0), %rdi"
        lines << "mov 8($0), %rsi"
        lines << "vpbroadcastq 16($0), %ymm0"
        lines << "mov $$1, %rax"
        lines << "vmovq %rax, %xmm2"
        lines << "vpbroadcastq %xmm2, %ymm2"
      %}
      {% for chunk in 0...((word_count + 31) // 32) %}
        {% register_count = (word_count - 32 * chunk) < 32 ? (word_count - 32 * chunk) // 4 : 8 %}
        {% lines << "vpxor %ymm1, %ymm1, %ymm1" %}
        {% for index in 0...register_count %}
          {% lines << "vpxor %ymm#{5 + index}, %ymm#{5 + index}, %ymm#{5 + index}" %}
        {% end %}
        {% for entry in 0...32 %}
          {% lines << "vpcmpeqq %ymm1, %ymm0, %ymm3" %}
          {% for index in 0...register_count %}
            {% lines << "vpand #{8 * (entry * word_count + 32 * chunk + 4 * index)}(%rsi), %ymm3, %ymm4" %}
            {% lines << "vpor %ymm4, %ymm#{5 + index}, %ymm#{5 + index}" %}
          {% end %}
          {% lines << "vpaddq %ymm2, %ymm1, %ymm1" %}
        {% end %}
        {% for index in 0...register_count %}
          {% lines << "vmovdqu %ymm#{5 + index}, #{8 * (32 * chunk + 4 * index)}(%rdi)" %}
        {% end %}
      {% end %}
      {% lines << "vzeroupper" %}
      %finished = 0_u64
      asm({{ lines.join("\n") }}
        : "=r"(%finished) : "0"({{ parameters }})
        : "rax", "rsi", "rdi", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10",
          "xmm11", "xmm12", "memory", "flags")
    end

    {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
      {% for word_count in [16, 24, 32, 48, 64] %}
        # Copies entry *index* (below 32, secret) of a table of
        # {{ word_count }}-word entries into *destination_pointer*, reading
        # every entry; needs AVX2.
        def self.select_entry_{{ word_count }}(destination_pointer : UInt64*, table_pointer : UInt64*, index : UInt64) : Nil
          operands = StaticArray[destination_pointer.address, table_pointer.address, index]
          operands_address = operands.to_unsafe.address
          select_entry_with_vectors_statement({{ word_count }}, operands_address)
        end

        # Sets result to a·b/R mod m for {{ word_count }}-word numbers (*b*
        # below m), with *scratch_pointer* to
        # {{ SCRATCH_WORD_COUNT_PER_WORD * word_count + SCRATCH_EXTRA_WORD_COUNT }}
        # words; *result* may be *a* or *b*.
        def self.multiply_{{ word_count }}(result_pointer : UInt64*, a_pointer : UInt64*, b_pointer : UInt64*, modulus_pointer : UInt64*,
                                           negated_inverse : UInt64, scratch_pointer : UInt64*) : Nil
          operands = StaticArray[result_pointer.address, a_pointer.address, b_pointer.address, modulus_pointer.address,
                                 negated_inverse, scratch_pointer.address]
          operands_address = operands.to_unsafe.address
          strip_statement({{ word_count }}, false, operands_address)
        end

        # Sets result to a·a/R mod m for {{ word_count }}-word numbers (*a*
        # below m), with *scratch_pointer* as for `multiply_{{ word_count }}`;
        # *result* may be *a*.
        def self.square_{{ word_count }}(result_pointer : UInt64*, a_pointer : UInt64*, modulus_pointer : UInt64*,
                                         negated_inverse : UInt64, scratch_pointer : UInt64*) : Nil
          operands = StaticArray[result_pointer.address, a_pointer.address, a_pointer.address, modulus_pointer.address,
                                 negated_inverse, scratch_pointer.address]
          operands_address = operands.to_unsafe.address
          strip_statement({{ word_count }}, true, operands_address)
        end
      {% end %}
    {% end %}
  end
end
