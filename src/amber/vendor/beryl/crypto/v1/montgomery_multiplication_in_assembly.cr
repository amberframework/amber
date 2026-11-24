module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # Montgomery multiplication and squaring for RSA written in AArch64
  # assembly (milestones F3 and F3b of plans/BERYL_TLS_CRYPTO.md), one copy
  # for each word count `MontgomeryArithmetic` specializes. Each computes
  # what `MontgomeryArithmetic.multiply` computes: a·b + M·m for the unique
  # M below R that makes it divisible by R, divided by R, less m once when
  # that is not below m. The result is the same integer however the
  # product and the reduction are ordered, so the forms are
  # interchangeable, and spec/beryl/crypto/v1/montgomery_arithmetic_spec.cr
  # compares each with the Crystal multiplication.
  #
  # Two forms:
  # - 16 words (the primes of a 2,048-bit key): the running sum lives in
  #   registers and the carries in the processor's carry flag, so each
  #   word product costs a `mul` or `umulh` and an `adcs`; squaring has its
  #   own copy (`square_16_words_statement`).
  # - 24, 32, 48 and 64 words: strips of eight words held in registers
  #   against a run of words of the other factor, the product formed first
  #   and reduced after (`strip_statement`), with a squaring that forms
  #   each product a_i·a_j once. On Apple M4 a strip row (eight word
  #   products) takes about 6.6 cycles; the memory kernel it replaced took
  #   about 1.3 cycles per word product.
  #
  # Constant time: loops count down from constants (word counts, public);
  # no other branch, and no address computed from data.
  # `scripts/check_secret_flow.rb` checks the text.
  module MontgomeryMultiplicationInAssembly
    {% if flag?(:aarch64) && !flag?(:beryl_portable_rsa) %}
      AVAILABLE = true
    {% else %}
      AVAILABLE = false
    {% end %}

    # Registers: x0 to x17 and x19 to x22 hold the sum (18 words) and four
    # temporaries; $0 points at the result, $1 at a, $2 at b, $3 at the
    # modulus, and $4 holds -m^-1 mod 2^64.
    macro multiply_16_words_statement(result, first_factor, second_factor, modulus, negated_inverse)
      {%
        registers = %w(x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 x16 x17 x19 x20 x21 x22)
        sum = registers[0...18]
        b_word = registers[18]
        product = registers[19]
        multiplier = registers[20]
        loaded = registers[21]
        lines = [] of StringLiteral
      %}
      {% for index in 0...18 %}
        {% lines << "mov #{sum[index].id}, xzr" %}
      {% end %}
      {% for row in 0...16 %}
        {% lines << "ldr #{b_word.id}, [$2, ##{8 * row}]" %}
        {% for column in 0...16 %}
          {% lines << "ldr #{loaded.id}, [$1, ##{8 * column}]" %}
          {% lines << "mul #{product.id}, #{b_word.id}, #{loaded.id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column].id}, #{sum[column].id}, #{product.id}" %}
        {% end %}
        {% lines << "adcs #{sum[16].id}, #{sum[16].id}, xzr" %}
        {% lines << "adc #{sum[17].id}, xzr, xzr" %}
        {% for column in 0...16 %}
          {% lines << "ldr #{loaded.id}, [$1, ##{8 * column}]" %}
          {% lines << "umulh #{product.id}, #{b_word.id}, #{loaded.id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column + 1].id}, #{sum[column + 1].id}, #{product.id}" %}
        {% end %}
        {% lines << "adc #{sum[17].id}, #{sum[17].id}, xzr" %}
        {% lines << "mul #{multiplier.id}, #{sum[0].id}, $4" %}
        {% for column in 0...16 %}
          {% lines << "ldr #{loaded.id}, [$3, ##{8 * column}]" %}
          {% lines << "mul #{product.id}, #{multiplier.id}, #{loaded.id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column].id}, #{sum[column].id}, #{product.id}" %}
        {% end %}
        {% lines << "adcs #{sum[16].id}, #{sum[16].id}, xzr" %}
        {% lines << "adc #{sum[17].id}, #{sum[17].id}, xzr" %}
        {% for column in 0...16 %}
          {% lines << "ldr #{loaded.id}, [$3, ##{8 * column}]" %}
          {% lines << "umulh #{product.id}, #{multiplier.id}, #{loaded.id}" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column + 1].id}, #{sum[column + 1].id}, #{product.id}" %}
        {% end %}
        {% lines << "adc #{sum[17].id}, #{sum[17].id}, xzr" %}
        {% sum = sum[1..-1] + [sum[0]] %}
      {% end %}
      {% for column in 0...16 %}
        {% lines << "ldr #{loaded.id}, [$3, ##{8 * column}]" %}
        {% lines << "#{(column == 0 ? "subs" : "sbcs").id} #{product.id}, #{sum[column].id}, #{loaded.id}" %}
        {% lines << "str #{product.id}, [$0, ##{8 * column}]" %}
      {% end %}
      {% lines << "sbcs xzr, #{sum[16].id}, xzr" %}
      {% for column in 0...16 %}
        {% lines << "ldr #{loaded.id}, [$0, ##{8 * column}]" %}
        {% lines << "csel #{sum[column].id}, #{sum[column].id}, #{loaded.id}, lo" %}
        {% lines << "str #{sum[column].id}, [$0, ##{8 * column}]" %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: "r"({{ result }}), "r"({{ first_factor }}), "r"({{ second_factor }}), "r"({{ modulus }}), "r"({{ negated_inverse }})
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
          "x16", "x17", "x19", "x20", "x21", "x22", "memory", "cc")
    end

    # Montgomery squaring of a 16-word number, a·a/R mod m: about a quarter
    # fewer word products than `multiply_16_words_statement`, since each
    # product a[i]·a[j] with i < j is formed once and doubled. Three steps,
    # with the 32-word square in *scratch*:
    # 1. the products a[i]·a[j], i < j, row by row, the running sum in
    #    registers as in the multiplication (each row finishes one word);
    # 2. doubling, and the squares a[i]·a[i] added on the diagonal;
    # 3. Montgomery reduction of the low 16 words alone, the multiples of m
    #    in registers, then the high 16 words added and one subtraction of m
    #    kept or dropped by `csel`. Reduction is linear, so this equals
    #    reducing all 32 words; the result is the same integer as the
    #    multiplication's, below m.
    # Registers: x0 to x17 the running sum, x19 to x22 temporaries; $0
    # points at the result, $1 at a, $2 at the modulus, $3 holds
    # -m^-1 mod 2^64 and $4 points at 32 words of scratch.
    macro square_16_words_statement(result, factor, modulus, negated_inverse, scratch)
      {%
        sum = %w(x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 x16 x17)
        lines = [] of StringLiteral
      %}
      {% for index in 0...16 %}
        {% lines << "mov #{sum[index].id}, xzr" %}
      {% end %}
      {% lines << "str xzr, [$4]" %}
      {% window = sum[0...17] %}
      {% for row in 0...15 %}
        {% lines << "ldr x22, [$1, ##{8 * row}]" %}
        {% for column in (row + 1)...16 %}
          {% lines << "ldr x19, [$1, ##{8 * column}]" %}
          {% lines << "mul x20, x22, x19" %}
          {% lines << "#{(column == row + 1 ? "adds" : "adcs").id} #{window[column - 1].id}, #{window[column - 1].id}, x20" %}
        {% end %}
        {% lines << "adcs #{window[15].id}, #{window[15].id}, xzr" %}
        {% lines << "adc #{window[16].id}, xzr, xzr" %}
        {% for column in (row + 1)...16 %}
          {% lines << "ldr x19, [$1, ##{8 * column}]" %}
          {% lines << "umulh x20, x22, x19" %}
          {% lines << "#{(column == row + 1 ? "adds" : "adcs").id} #{window[column].id}, #{window[column].id}, x20" %}
        {% end %}
        {% lines << "adc #{window[16].id}, #{window[16].id}, xzr" %}
        {% lines << "str #{window[0].id}, [$4, ##{8 * (row + 1)}]" %}
        {% window = window[1..-1] + [window[0]] %}
      {% end %}
      {% for index in 0...16 %}
        {% lines << "str #{window[index].id}, [$4, ##{8 * (16 + index)}]" %}
      {% end %}
      {% for index in 0...32 %}
        {% lines << "ldr x19, [$4, ##{8 * index}]" %}
        {% lines << "#{(index == 0 ? "adds" : "adcs").id} x19, x19, x19" %}
        {% lines << "str x19, [$4, ##{8 * index}]" %}
      {% end %}
      {% for index in 0...16 %}
        {% lines << "ldr x22, [$1, ##{8 * index}]" %}
        {% lines << "mul x20, x22, x22" %}
        {% lines << "umulh x21, x22, x22" %}
        {% lines << "ldr x19, [$4, ##{16 * index}]" %}
        {% lines << "#{(index == 0 ? "adds" : "adcs").id} x19, x19, x20" %}
        {% lines << "str x19, [$4, ##{16 * index}]" %}
        {% lines << "ldr x19, [$4, ##{16 * index + 8}]" %}
        {% lines << "adcs x19, x19, x21" %}
        {% lines << "str x19, [$4, ##{16 * index + 8}]" %}
      {% end %}
      {% for index in 0...16 %}
        {% lines << "ldr #{sum[index].id}, [$4, ##{8 * index}]" %}
      {% end %}
      {% lines << "mov #{sum[16].id}, xzr" %}
      {% lines << "mov #{sum[17].id}, xzr" %}
      {% for row in 0...16 %}
        {% lines << "mul x21, #{sum[0].id}, $3" %}
        {% for column in 0...16 %}
          {% lines << "ldr x19, [$2, ##{8 * column}]" %}
          {% lines << "mul x20, x21, x19" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column].id}, #{sum[column].id}, x20" %}
        {% end %}
        {% lines << "adcs #{sum[16].id}, #{sum[16].id}, xzr" %}
        {% lines << "adc #{sum[17].id}, #{sum[17].id}, xzr" %}
        {% for column in 0...16 %}
          {% lines << "ldr x19, [$2, ##{8 * column}]" %}
          {% lines << "umulh x20, x21, x19" %}
          {% lines << "#{(column == 0 ? "adds" : "adcs").id} #{sum[column + 1].id}, #{sum[column + 1].id}, x20" %}
        {% end %}
        {% lines << "adc #{sum[17].id}, #{sum[17].id}, xzr" %}
        {% sum = sum[1..-1] + [sum[0]] %}
      {% end %}
      {% for index in 0...16 %}
        {% lines << "ldr x19, [$4, ##{8 * (16 + index)}]" %}
        {% lines << "#{(index == 0 ? "adds" : "adcs").id} #{sum[index].id}, #{sum[index].id}, x19" %}
      {% end %}
      {% lines << "adc #{sum[16].id}, #{sum[16].id}, xzr" %}
      {% for column in 0...16 %}
        {% lines << "ldr x19, [$2, ##{8 * column}]" %}
        {% lines << "#{(column == 0 ? "subs" : "sbcs").id} x20, #{sum[column].id}, x19" %}
        {% lines << "str x20, [$0, ##{8 * column}]" %}
      {% end %}
      {% lines << "sbcs xzr, #{sum[16].id}, xzr" %}
      {% for column in 0...16 %}
        {% lines << "ldr x19, [$0, ##{8 * column}]" %}
        {% lines << "csel #{sum[column].id}, #{sum[column].id}, x19, lo" %}
        {% lines << "str #{sum[column].id}, [$0, ##{8 * column}]" %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: "r"({{ result }}), "r"({{ factor }}), "r"({{ modulus }}), "r"({{ negated_inverse }}), "r"({{ scratch }})
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
          "x16", "x17", "x19", "x20", "x21", "x22", "memory", "cc")
    end

    # The text of a Montgomery multiplication (or, with *square*, a squaring)
    # of *word_count*-word numbers, a multiple of 8, as separate steps
    # (separated operand scanning) on a sum T of 2n + 1 words in memory:
    # first T = a·b, then n multiples u·m·2^(64i) added so that the low n
    # words become zero, then T/R = T[n..2n], less m when it is not below m.
    #
    # Both steps are made of strips: eight words x of one factor held in
    # x19 to x26, times each word y of a run of the other, one word y per
    # row. A row adds x·y to a window of ten registers (x0 to x9, renamed
    # from row to row as the window moves up a word): the low halves by one
    # chain of `adcs`, the high halves by a second, so each word product
    # costs a `mul`, a `umulh` and two additions with carry. The window
    # holds only the strip's own sum; the word leaving it is added to T's
    # word at that place, and the carry of that addition enters the next
    # row's first `adcs`. The window stays below 2^513, so its top word never
    # overflows, and when a strip of the product ends, its last eight words
    # (with the last carry) go to a part of T that no earlier strip reached.
    #
    # - Product a·b: strip c takes x = a[8c..8c+7] and y = b, into T from
    #   word 8c. Squaring: strip c takes y = a[8c..n), its first eight rows
    #   using only the words of x below the row (the products a_i·a_j with
    #   i < j); one pass then doubles T (`extr` by one bit) and adds each
    #   a_i² on the diagonal.
    # - Reduction, eight words at a time: T[8q..8q+7] is loaded into the
    #   window and, row by row, u_j = T[8q+j]·(-m^-1) mod 2^64 is formed and
    #   u_j·m[0..7] added, which clears that word (the low half of u_j·m[0]
    #   is -T[8q+j] mod 2^64 and is not formed: the word becomes zero, with a
    #   carry exactly when it was not zero, which `cmp` with 1 sets); the
    #   eight u_j (in x19 to x26) are then a strip against y = m[8..n). That strip ends inside the
    #   top half of T, so its last nine words are added to T there; the carry
    #   out of that addition, at word 8q + n + 9, is kept in x27 and added at
    #   the next block's end, eight words higher, which lies above every word
    #   a later block reads to form its u.
    #
    # Operands: $0 points at six words: the result, a, b, m, -m^-1 mod 2^64
    # and T (2n + 2 words of scratch). The result may be a or b: it is
    # written last. Registers x0 to x17 and x19 to x27 are scratch.
    #
    # Constant time: the two loops (over the strips of a·b, and over the
    # reduction blocks) count down from constants; there is no other branch
    # and no address computed from data, and `csel` keeps or drops the final
    # subtraction. `scripts/check_secret_flow.rb` checks the text.
    macro strip_statement(word_count, square, parameters)
      {%
        n = word_count
        xs = %w(x19 x20 x21 x22 x23 x24 x25 x26)
        initial_window = %w(x0 x1 x2 x3 x4 x5 x6 x7 x8 x9)
        lines = [] of StringLiteral
      %}
      {% lines << "ldr x13, [$0, #40]" %}
      {% for k in 0...n %}
        {% lines << "str xzr, [x13, ##{8 * k}]" %}
      {% end %}
      {% lines << "str xzr, [x13, ##{16 * n}]" %}
      {% if square %}
        {% chunk_list = (0...(n // 8)).to_a %}
      {% else %}
        {%
          chunk_list = [0]
          lines << "ldr x17, [$0, #8]"
          lines << "ldr x14, [$0, #16]"
          lines << "mov x16, ##{n // 8}"
          lines << "1:"
        %}
      {% end %}
      {% for chunk in chunk_list %}
        {% if square %}
          {%
            lines << "ldr x17, [$0, #8]"
            lines << "add x17, x17, ##{64 * chunk}"
            lines << "mov x14, x17"
            lines << "ldr x13, [$0, #40]"
            lines << "add x13, x13, ##{128 * chunk}"
            row_counts = [] of NumberLiteral
          %}
          {% for row in 0...(n - 8 * chunk) %}
            {% row_counts << (row < 8 ? row : 8) %}
          {% end %}
        {% else %}
          {% row_counts = [] of NumberLiteral %}
          {% for row in 0...n %}
            {% row_counts << 8 %}
          {% end %}
        {% end %}
        {% window = initial_window %}
        {% for index in 0...4 %}
          {% lines << "ldp #{xs[2 * index].id}, #{xs[2 * index + 1].id}, [x17], #16" %}
        {% end %}
        {% for index in 0...9 %}
          {% lines << "mov #{window[index].id}, xzr" %}
        {% end %}
        {% lines << "adds xzr, xzr, xzr" %}
        {% for count in row_counts %}
          {% if count == 0 %}
            {%
              lines << "add x14, x14, #8"
              lines << "mov #{window[9].id}, xzr"
            %}
          {% else %}
            {% lines << "ldr x10, [x14], #8" %}
            {% for i in 0...count %}
              {% lines << "mul x11, #{xs[i].id}, x10" %}
              {% lines << "adcs #{window[i].id}, #{window[i].id}, x11" %}
            {% end %}
            {% if count == 8 %}
              {% lines << "adc #{window[8].id}, #{window[8].id}, xzr" %}
            {% else %}
              {% lines << "adcs #{window[count].id}, #{window[count].id}, xzr" %}
              {% lines << "mov #{window[9].id}, xzr" %}
            {% end %}
            {% for i in 0...count %}
              {% lines << "umulh x12, #{xs[i].id}, x10" %}
              {% lines << "#{(i == 0 ? "adds" : "adcs").id} #{window[i + 1].id}, #{window[i + 1].id}, x12" %}
            {% end %}
            {% lines << (count == 8 ? "adc #{window[9].id}, xzr, xzr" : "adc #{window[count + 1].id}, #{window[count + 1].id}, xzr") %}
          {% end %}
          {%
            lines << "ldr x15, [x13]"
            lines << "adds #{window[0].id}, #{window[0].id}, x15"
            lines << "str #{window[0].id}, [x13], #8"
            window = window[1..-1] + [window[0]]
          %}
        {% end %}
        {% for index in 0...8 %}
          {% lines << "adcs #{window[index].id}, #{window[index].id}, xzr" %}
        {% end %}
        {% for index in 0...4 %}
          {% lines << "stp #{window[2 * index].id}, #{window[2 * index + 1].id}, [x13], #16" %}
        {% end %}
      {% end %}
      {% if !square %}
        {%
          lines << "sub x13, x13, ##{8 * n}"
          lines << "sub x14, x14, ##{8 * n}"
          lines << "subs x16, x16, #1"
          lines << "b.ne 1b"
        %}
      {% end %}
      {% if square %}
        {%
          lines << "ldr x13, [$0, #40]"
          lines << "ldr x14, [$0, #8]"
          lines << "mov x15, xzr"
          lines << "adds xzr, xzr, xzr"
        %}
        {% for k in 0...n %}
          {%
            lines << "ldr x10, [x14], #8"
            lines << "mul x11, x10, x10"
            lines << "umulh x12, x10, x10"
            lines << "ldp x0, x1, [x13]"
            lines << "extr x15, x0, x15, #63"
            lines << "extr x0, x1, x0, #63"
            lines << "adcs x15, x15, x11"
            lines << "adcs x0, x0, x12"
            lines << "stp x15, x0, [x13], #16"
            lines << "mov x15, x1"
          %}
        {% end %}
      {% end %}
      {%
        lines << "ldr x17, [$0, #32]"
        lines << "ldr x13, [$0, #40]"
        lines << "mov x27, xzr"
        lines << "mov x16, ##{n // 8}"
        lines << "1:"
        lines << "ldr x14, [$0, #24]"
        window = initial_window
      %}
      {% for index in 0...4 %}
        {% lines << "ldp #{window[2 * index].id}, #{window[2 * index + 1].id}, [x13, ##{16 * index}]" %}
      {% end %}
      {% lines << "mov #{window[8].id}, xzr" %}
      {% for j in 0...8 %}
        {% lines << "mul #{xs[j].id}, #{window[0].id}, x17" %}
        {% lines << "cmp #{window[0].id}, #1" %}
        {% for i in 1...8 %}
          {% lines << "ldr x10, [x14, ##{8 * i}]" %}
          {% lines << "mul x11, x10, #{xs[j].id}" %}
          {% lines << "adcs #{window[i].id}, #{window[i].id}, x11" %}
        {% end %}
        {% lines << "adc #{window[8].id}, #{window[8].id}, xzr" %}
        {% for i in 0...8 %}
          {% lines << "ldr x10, [x14, ##{8 * i}]" %}
          {% lines << "umulh x12, x10, #{xs[j].id}" %}
          {% lines << "#{(i == 0 ? "adds" : "adcs").id} #{window[i + 1].id}, #{window[i + 1].id}, x12" %}
        {% end %}
        {% lines << "adc #{window[9].id}, xzr, xzr" %}
        {% window = window[1..-1] + [window[0]] %}
      {% end %}
      {%
        lines << "add x14, x14, #64"
        lines << "add x13, x13, #64"
        lines << "adds xzr, xzr, xzr"
      %}
      {% for row in 0...(n - 8) %}
        {% lines << "ldr x10, [x14], #8" %}
        {% for i in 0...8 %}
          {% lines << "mul x11, #{xs[i].id}, x10" %}
          {% lines << "adcs #{window[i].id}, #{window[i].id}, x11" %}
        {% end %}
        {% lines << "adc #{window[8].id}, #{window[8].id}, xzr" %}
        {% for i in 0...8 %}
          {% lines << "umulh x12, #{xs[i].id}, x10" %}
          {% lines << "#{(i == 0 ? "adds" : "adcs").id} #{window[i + 1].id}, #{window[i + 1].id}, x12" %}
        {% end %}
        {%
          lines << "adc #{window[9].id}, xzr, xzr"
          lines << "ldr x15, [x13]"
          lines << "adds #{window[0].id}, #{window[0].id}, x15"
          lines << "str #{window[0].id}, [x13], #8"
          window = window[1..-1] + [window[0]]
        %}
      {% end %}
      {%
        lines << "adc x15, xzr, xzr"
        lines << "adds #{window[0].id}, #{window[0].id}, x15"
        lines << "adcs #{window[1].id}, #{window[1].id}, x27"
      %}
      {% for index in 2...9 %}
        {% lines << "adcs #{window[index].id}, #{window[index].id}, xzr" %}
      {% end %}
      {% for index in 0...9 %}
        {% lines << "ldr x10, [x13, ##{8 * index}]" %}
        {% lines << "#{(index == 0 ? "adds" : "adcs").id} #{window[index].id}, #{window[index].id}, x10" %}
        {% lines << "str #{window[index].id}, [x13, ##{8 * index}]" %}
      {% end %}
      {%
        lines << "adc x27, xzr, xzr"
        lines << "sub x13, x13, ##{8 * n - 64}"
        lines << "subs x16, x16, #1"
        lines << "b.ne 1b"
        lines << "ldr x13, [$0, #40]"
        lines << "add x13, x13, ##{8 * n}"
        lines << "ldr x14, [$0, #24]"
        lines << "ldr x17, [$0]"
      %}
      {% for k in 0...n %}
        {% lines << "ldr x10, [x13, ##{8 * k}]" %}
        {% lines << "ldr x11, [x14, ##{8 * k}]" %}
        {% lines << "#{(k == 0 ? "subs" : "sbcs").id} x10, x10, x11" %}
        {% lines << "str x10, [x17, ##{8 * k}]" %}
      {% end %}
      {% lines << "ldr x10, [x13, ##{8 * n}]" %}
      {% lines << "sbcs xzr, x10, xzr" %}
      {% for k in 0...n %}
        {% lines << "ldr x10, [x13, ##{8 * k}]" %}
        {% lines << "ldr x11, [x17, ##{8 * k}]" %}
        {% lines << "csel x10, x10, x11, lo" %}
        {% lines << "str x10, [x17, ##{8 * k}]" %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: "r"({{ parameters }})
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17",
          "x19", "x20", "x21", "x22", "x23", "x24", "x25", "x26", "x27", "memory", "cc")
    end

    # Copies entry $2 of the *entry_count* entries of *word_count* words at
    # $1 into $0, reading every word of every entry and keeping one by
    # `csel`, 16 words at a time in x0 to x15 (x16 holds the word just
    # loaded).
    macro select_entry_statement(word_count, entry_count, destination, table, index)
      {%
        kept = %w(x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15)
        lines = [] of StringLiteral
      %}
      {% for chunk_index in 0...((word_count + 15) // 16) %}
        {% chunk_start = chunk_index * 16 %}
        {% chunk_size = word_count - chunk_start < 16 ? word_count - chunk_start : 16 %}
        {% for word in 0...chunk_size %}
          {% lines << "mov #{kept[word].id}, xzr" %}
        {% end %}
        {% for entry in 0...entry_count %}
          {% lines << "cmp $2, ##{entry}" %}
          {% for word in 0...chunk_size %}
            {% lines << "ldr x16, [$1, ##{(entry * word_count + chunk_start + word) * 8}]" %}
            {% lines << "csel #{kept[word].id}, x16, #{kept[word].id}, eq" %}
          {% end %}
        {% end %}
        {% for word in 0...chunk_size %}
          {% lines << "str #{kept[word].id}, [$0, ##{(chunk_start + word) * 8}]" %}
        {% end %}
      {% end %}
      asm({{ lines.join("\n") }}
        :: "r"({{ destination }}), "r"({{ table }}), "r"({{ index }})
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
          "x16", "memory", "cc")
    end

    {% if flag?(:aarch64) && !flag?(:beryl_portable_rsa) %}
      # Sets result to a·b/R mod m for 16-word numbers; *result* may be *a*
      # or *b*.
      def self.multiply_16(result_pointer : UInt64*, a_pointer : UInt64*, b_pointer : UInt64*, modulus_pointer : UInt64*,
                           negated_inverse : UInt64) : Nil
        multiply_16_words_statement(result_pointer, a_pointer, b_pointer, modulus_pointer, negated_inverse)
      end

      # Sets result to a·a/R mod m for 16-word numbers, with *scratch_pointer*
      # to 32 words; *result* may be *a*.
      def self.square_16(result_pointer : UInt64*, a_pointer : UInt64*, modulus_pointer : UInt64*, negated_inverse : UInt64,
                         scratch_pointer : UInt64*) : Nil
        square_16_words_statement(result_pointer, a_pointer, modulus_pointer, negated_inverse, scratch_pointer)
      end

      {% for word_count in [16, 24, 32, 48, 64] %}
        # Copies entry *index* (below 32, the entries of
        # `MontgomeryArithmetic`'s five-bit window) of a table of
        # {{ word_count }}-word entries into *destination*, reading every entry.
        def self.select_entry_{{ word_count }}(destination_pointer : UInt64*, table_pointer : UInt64*, index : UInt64) : Nil
          select_entry_statement({{ word_count }}, 32, destination_pointer, table_pointer, index)
        end
      {% end %}

      {% for word_count in [24, 32, 48, 64] %}
        # Sets result to a·b/R mod m for {{ word_count }}-word numbers (*b*
        # below m), with *scratch_pointer* to {{ 2 * word_count + 2 }} words;
        # *result* may be *a* or *b*.
        def self.multiply_{{ word_count }}(result_pointer : UInt64*, a_pointer : UInt64*, b_pointer : UInt64*, modulus_pointer : UInt64*,
                                           negated_inverse : UInt64, scratch_pointer : UInt64*) : Nil
          operands = StaticArray[result_pointer.address, a_pointer.address, b_pointer.address, modulus_pointer.address,
                                 negated_inverse, scratch_pointer.address]
          operands_pointer = operands.to_unsafe
          strip_statement({{ word_count }}, false, operands_pointer)
        end

        # Sets result to a·a/R mod m for {{ word_count }}-word numbers (*a*
        # below m), with *scratch_pointer* to {{ 2 * word_count + 2 }} words;
        # *result* may be *a*.
        def self.square_{{ word_count }}(result_pointer : UInt64*, a_pointer : UInt64*, modulus_pointer : UInt64*,
                                         negated_inverse : UInt64, scratch_pointer : UInt64*) : Nil
          operands = StaticArray[result_pointer.address, a_pointer.address, a_pointer.address, modulus_pointer.address,
                                 negated_inverse, scratch_pointer.address]
          operands_pointer = operands.to_unsafe
          strip_statement({{ word_count }}, true, operands_pointer)
        end
      {% end %}
    {% end %}
  end
end
