module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # RSA's private operation with AVX-512 IFMA (`vpmadd52luq` and
  # `vpmadd52huq`, the low and high 52 bits of a 52 × 52-bit product added
  # to a 64-bit lane), taken where
  # `ProcessorFeatures::HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD` says the
  # processor has it, for keys whose two primes have the same size: 1,024,
  # 1,536 or 2,048 bits (2,048, 3,072 and 4,096-bit keys). The two
  # exponentiations of the Chinese remainder theorem run side by side, each
  # multiplication of one prime beside the same multiplication of the
  # other, so that the processor overlaps two independent chains of
  # dependent instructions.
  #
  # Numbers are written in radix 2^52, one digit in each 64-bit lane: a
  # prime of n words takes d = ⌈64n/52⌉ digits (20, 30 or 40), padded with
  # zero digits to a whole number of 512-bit registers (24, 32 or 40 lanes).
  # The multiplication is the almost Montgomery multiplication of Gueron
  # ("Efficient software implementations of modular exponentiation",
  # Journal of Cryptographic Engineering 2, 2012), with R' = 2^(52d): it
  # returns a number below 2m and congruent to a·b/R' modulo m, for a and b
  # below 2m, since 52d is at least two bits more than the prime's size
  # (Lemma 1 of Gueron, "Enhanced Montgomery Multiplication", CHES 2002).
  # Its arrangement is that of OpenSSL's `rsaz-2k-avx512.pl` (Kirillov and
  # Matyukov, Intel, 2020), written for 512-bit registers:
  #
  # - For each digit b_i of b, with b_i and y_i broadcast to every lane:
  #   the lowest digit of the running sum is kept in a general register,
  #   where a_0·b_i is added and y_i = (that digit · -m^-1) mod 2^52 is
  #   formed; then the low halves of a·b_i and m·y_i are added to every
  #   lane, the lanes move down one digit (`valignq`), the digit that moves
  #   into the lowest place is added to the general register (which holds
  #   the carry out of the digit that left), and the high halves of a·b_i
  #   and m·y_i are added.
  # - At the end the lanes hold more than 52 bits; the bits above 52 move up
  #   one lane, and the carries that this makes, at most one per lane, are
  #   found by comparing every lane with 2^52 - 1 and propagated with one
  #   addition of the bit masks in a general register, as in OpenSSL.
  #
  # Exponents are secret and use the fixed window of `MontgomeryArithmetic`
  # (five bits, every window the same five squarings and one
  # multiplication); the table entry is chosen by reading every entry and
  # keeping one with a blend under a mask (`dual_select_statement`).
  #
  # Constant time: no statement here has a branch, every memory address is
  # a fixed offset from a pointer operand, and the multiply-adds, shifts,
  # compares, blends and mask moves take the same time whatever they hold.
  # `scripts/check_secret_flow.rb` checks the text. Valgrind's processor has
  # no AVX-512, so under Valgrind this path is not taken; the timing check
  # and the differential against libcrypto cover it on processors that have
  # it.
  module MontgomeryMultiplicationWithIntegerFusedMultiplyAdd
    DIGIT_BIT_COUNT = 52
    DIGIT_MASK      = (1_u64 << DIGIT_BIT_COUNT) - 1

    # The word counts of the primes this path takes (those of 2,048, 3,072
    # and 4,096-bit keys).
    SUPPORTED_WORD_COUNTS = [16, 24, 32]

    # The word counts of the moduli whose public operation takes this path
    # (2,048, 3,072 and 4,096 bits), one multiplication at a time.
    PUBLIC_WORD_COUNTS = [32, 48, 64]

    # The number of 52-bit digits that hold a number of *word_count* words.
    def self.digit_count_for(word_count : Int32) : Int32
      (64 * word_count + DIGIT_BIT_COUNT - 1) // DIGIT_BIT_COUNT
    end

    # The digit count rounded up to whole 512-bit registers of eight lanes.
    def self.padded_digit_count_for(word_count : Int32) : Int32
      (digit_count_for(word_count) + 7) // 8 * 8
    end

    # The text of *half_count* (two, or one) almost Montgomery
    # multiplications side by side, each of numbers of *digit_count* digits
    # in *padded_digit_count* lanes. With two, every operand is two numbers,
    # one after the other (the first prime's, then the second's). $0 points
    # at six words: the result, a, b, m, and -m^-1 mod 2^64 for each
    # multiplication. The result may be a or b: it is written last.
    #
    # Registers: rsi, rdi and rcx point at a, b and m, rbx at the result;
    # rax holds 2^52 - 1. The first multiplication keeps its lowest digit in
    # r8 with r10, r11 and rbp for scratch, the second in r9 with r12, r13
    # and r14. zmm0 is zero; zmm1 and zmm2 hold b_i and y_i broadcast for
    # the first, zmm3 and zmm4 for the second; the running sums are zmm5 on
    # (the first) and zmm10 on (the second), one register per eight lanes;
    # zmm15 on and zmm25 serve the final carry propagation, with the lane
    # masks in r10 and r11 (the first) and r12 and r13 (the second, or the
    # high lanes of a single multiplication of more than 64 lanes), and rax.
    macro multiplication_statement(half_count, digit_count, padded_digit_count, parameters, square = false)
      {%
        register_count = padded_digit_count // 8
        mask_word_count = (register_count + 7) // 8
        is_last_register_narrow = digit_count - 8 * (register_count - 1) <= 4
        whole_register_count = digit_count // 8
        lane_shift = digit_count % 8
        lines = [] of StringLiteral
        halves = [
          {offset: 0, accumulator: "r8", first: "r10", second: "r11", third: "rbp",
           broadcast_b: "zmm1", broadcast_y: "zmm2", sums: (5...(5 + register_count)).to_a.map { |index| "zmm#{index}" },
           carries: (15...(15 + register_count)).to_a.map { |index| "zmm#{index}" }, inverse: 32,
           carries_or_kept: (15...20).to_a.map { |index| "zmm#{index}" }, first_columns: "zmm29",
           greater: half_count == 1 ? ["r10", "r12"] : ["r10"], equal: half_count == 1 ? ["r11", "r13"] : ["r11"]},
          {offset: 8 * padded_digit_count, accumulator: "r9", first: "r12", second: "r13", third: "r14",
           broadcast_b: "zmm3", broadcast_y: "zmm4", sums: (10...(10 + register_count)).to_a.map { |index| "zmm#{index}" },
           carries: (20...(20 + register_count)).to_a.map { |index| "zmm#{index}" }, inverse: 40,
           carries_or_kept: (20...25).to_a.map { |index| "zmm#{index}" }, first_columns: "zmm30",
           greater: ["r12"], equal: ["r13"]},
        ]
        halves = halves[0...half_count]
        lines << "mov 8($0), %rsi"
        lines << "mov 16($0), %rdi"
        lines << "mov 24($0), %rcx"
        lines << "mov 0($0), %rbx"
        lines << "movabsq $$0xfffffffffffff, %rax"
        lines << "vpxorq %zmm0, %zmm0, %zmm0"
        lines << "xor %r8, %r8"
        lines << "xor %r9, %r9"
      %}
      {% for half in halves %}
        {% for sum in half[:sums] %}
          {% lines << "vpxorq %#{sum.id}, %#{sum.id}, %#{sum.id}" %}
        {% end %}
      {% end %}
      {% if square %}
        # The diagonal D = sum of (a_k² + t_(k-1)·a_k)·B^(2k), where t_k is
        # the top bit of a_k (the carry of 2a_k): column 2k takes the low
        # half of a_k² and t_(k-1)·a_k, column 2k + 1 the high half. Its
        # columns 8 to d - 1 start the sums; the first eight are added at
        # the second digit (the first digit takes a_0² from mulx, as a
        # multiplication does, so it need not wait for them); the rest are
        # kept (in the registers the carries use later) and added at the end.
        {%
          lines << "movabsq $$0x0b030a0209010800, %rdx"
          lines << "vmovq %rdx, %xmm1"
          lines << "vpmovzxbq %xmm1, %zmm1"
          lines << "movabsq $$0x0f070e060d050c04, %rdx"
          lines << "vmovq %rdx, %xmm2"
          lines << "vpmovzxbq %xmm2, %zmm2"
          lines << "mov $$#{(1 << lane_shift) - 1}, %edx"
          lines << "kmovb %edx, %k7"
          lines << "vpbroadcastq %rax, %zmm25"
        %}
        {% for half in halves %}
          {% lines << "vpxorq %zmm31, %zmm31, %zmm31" %}
          {% for index in 0...register_count %}
            {%
              lines << "vmovdqu64 #{half[:offset] + 64 * index}(%rsi), %zmm27"
              lines << "vpxorq %zmm26, %zmm26, %zmm26"
              lines << "vpmadd52luq %zmm27, %zmm27, %zmm26"
              lines << "vpxorq %zmm28, %zmm28, %zmm28"
              lines << "vpmadd52huq %zmm27, %zmm27, %zmm28"
              lines << "vpsrlq $$51, %zmm27, %zmm3"
              lines << "valignq $$7, %zmm31, %zmm3, %zmm4"
              lines << "vmovdqa64 %zmm3, %zmm31"
              lines << "vpsllq $$1, %zmm27, %zmm3"
              lines << "vpandq %zmm25, %zmm3, %zmm3"
              lines << "vpaddq %zmm4, %zmm3, %zmm3"
              lines << "vmovdqu64 %zmm3, #{half[:offset] + 64 * index}(%rdi)"
              lines << "vpsubq %zmm4, %zmm0, %zmm4"
              lines << "vpandq %zmm27, %zmm4, %zmm4"
              lines << "vpaddq %zmm4, %zmm26, %zmm26"
            %}
            {% for part in [0, 1] %}
              {% column_register = 2 * index + part %}
              {% index_vector = part == 0 ? "zmm1" : "zmm2" %}
              {% if column_register == 0 %}
                {% target = half[:first_columns] %}
              {% elsif column_register < whole_register_count %}
                {% target = half[:sums][column_register] %}
              {% else %}
                {% target = half[:carries_or_kept][column_register - whole_register_count] %}
              {% end %}
              {%
                lines << "vmovdqa64 %#{index_vector.id}, %#{target.id}"
                lines << "vpermi2q %zmm28, %zmm26, %#{target.id}"
              %}
              {% if column_register == whole_register_count && lane_shift > 0 %}
                {% lines << "vmovdqa64 %#{target.id}, %#{half[:sums][column_register].id}{%k7}{z}" %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
        # Each row's mask, lanes above its digit's: k1 to k7 for digits at
        # lanes 0 to 6 (a digit at lane 7 has none in its register).
        {% for lane in 0...7 %}
          {% lines << "mov $$#{(255 << (lane + 1)) % 256}, %edx" %}
          {% lines << "kmovb %edx, %k#{lane + 1}" %}
        {% end %}
      {% end %}
      {% for digit in 0...digit_count %}
        {%
          lane = digit % 8
          first_register = lane == 7 ? digit // 8 + 1 : digit // 8
        %}
        {% if square && digit == 1 %}
          {% for half in halves %}
            {% lines << "valignq $$1, %#{half[:first_columns].id}, %zmm0, %zmm26" %}
            {% lines << "vpaddq %zmm26, %#{half[:sums][0].id}, %#{half[:sums][0].id}" %}
          {% end %}
        {% end %}
        {% for half in halves %}
          {%
            accumulator = half[:accumulator]
            first = half[:first]
            second = half[:second]
            third = half[:third]
            offset = half[:offset]
          %}
          {% lines << "vpbroadcastq #{offset + 8 * digit}(%rdi), %#{half[:broadcast_b].id}" %}
          {% if !square || digit == 0 %}
            {%
              lines << "mov #{offset}(%rsi), %rdx"
              lines << "mulx #{offset + 8 * digit}(#{(square ? "%rsi" : "%rdi").id}), %#{first.id}, %#{second.id}"
              lines << "add %#{first.id}, %#{accumulator.id}"
              lines << "adc $$0, %#{second.id}"
            %}
          {% else %}
            {% lines << "xor %#{second.id}, %#{second.id}" %}
          {% end %}
          {%
            lines << "mov #{half[:inverse]}($0), %#{first.id}"
            lines << "imul %#{accumulator.id}, %#{first.id}"
            lines << "and %rax, %#{first.id}"
            lines << "vpbroadcastq %#{first.id}, %#{half[:broadcast_y].id}"
            lines << "mov #{offset}(%rcx), %rdx"
            lines << "mulx %#{first.id}, %#{first.id}, %#{third.id}"
            lines << "add %#{first.id}, %#{accumulator.id}"
            lines << "adc %#{third.id}, %#{second.id}"
            lines << "shr $$52, %#{accumulator.id}"
            lines << "shl $$12, %#{second.id}"
            lines << "or %#{second.id}, %#{accumulator.id}"
          %}
        {% end %}
        {% for half in halves %}
          {% for index in (square ? first_register : 0)...register_count %}
            {%
              width = is_last_register_narrow && index == register_count - 1 ? "ymm" : "zmm"
              mask = square && index == digit // 8 ? "{%k#{lane + 1}}" : ""
            %}
            {% lines << "vpmadd52luq #{half[:offset] + 64 * index}(%rsi), %#{half[:broadcast_b].gsub(/zmm/, width).id}, %#{half[:sums][index].gsub(/zmm/, width).id}#{mask.id}" %}
          {% end %}
          {% for index in 0...register_count %}
            {% width = is_last_register_narrow && index == register_count - 1 ? "ymm" : "zmm" %}
            {% lines << "vpmadd52luq #{half[:offset] + 64 * index}(%rcx), %#{half[:broadcast_y].gsub(/zmm/, width).id}, %#{half[:sums][index].gsub(/zmm/, width).id}" %}
          {% end %}
        {% end %}
        {% for half in halves %}
          {% lines << "vpextrq $$1, %#{half[:sums][0].gsub(/zmm/, "xmm").id}, %#{half[:first].id}" %}
          {% for index in 0...register_count %}
            {% if is_last_register_narrow && index == register_count - 1 %}
              {% narrow = half[:sums][index].gsub(/zmm/, "ymm") %}
              {% lines << "valignq $$1, %#{narrow.id}, %ymm0, %#{narrow.id}" %}
            {% else %}
              {% higher = index == register_count - 1 ? "zmm0" : half[:sums][index + 1] %}
              {% lines << "valignq $$1, %#{half[:sums][index].id}, %#{higher.id}, %#{half[:sums][index].id}" %}
            {% end %}
          {% end %}
          {% lines << "add %#{half[:first].id}, %#{half[:accumulator].id}" %}
        {% end %}
        {% for half in halves %}
          {% for index in (square ? first_register : 0)...register_count %}
            {%
              width = is_last_register_narrow && index == register_count - 1 ? "ymm" : "zmm"
              mask = square && index == digit // 8 ? "{%k#{lane + 1}}" : ""
            %}
            {% lines << "vpmadd52huq #{half[:offset] + 64 * index}(%rsi), %#{half[:broadcast_b].gsub(/zmm/, width).id}, %#{half[:sums][index].gsub(/zmm/, width).id}#{mask.id}" %}
          {% end %}
          {% for index in 0...register_count %}
            {% width = is_last_register_narrow && index == register_count - 1 ? "ymm" : "zmm" %}
            {% lines << "vpmadd52huq #{half[:offset] + 64 * index}(%rcx), %#{half[:broadcast_y].gsub(/zmm/, width).id}, %#{half[:sums][index].gsub(/zmm/, width).id}" %}
          {% end %}
        {% end %}
      {% end %}
      # Carry propagation, then the stores.
      {%
        lines << "vpbroadcastq %rax, %zmm25"
        lines << "mov $$1, %r10d"
        lines << "kmovb %r10d, %k1"
      %}
      {% for half in halves %}
        {%
          sums = half[:sums]
          carries = half[:carries]
          greater = half[:greater]
          equal = half[:equal]
          lines << "vpbroadcastq %#{half[:accumulator].id}, %#{sums[0].id}{%k1}"
        %}
        {% if square %}
          {% kept = half[:carries_or_kept] %}
          {% kept_count = 2 * register_count - whole_register_count %}
          {% for index in 0...register_count %}
            {% higher = index + 1 < kept_count ? kept[index + 1] : "zmm0" %}
            {% if index < kept_count %}
              {% if lane_shift == 0 %}
                {% lines << "vpaddq %#{kept[index].id}, %#{sums[index].id}, %#{sums[index].id}" %}
              {% else %}
                {% lines << "valignq $$#{lane_shift}, %#{kept[index].id}, %#{higher.id}, %zmm26" %}
                {% lines << "vpaddq %zmm26, %#{sums[index].id}, %#{sums[index].id}" %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
        {% for index in 0...register_count %}
          {% lines << "vpsrlq $$52, %#{sums[index].id}, %#{carries[index].id}" %}
        {% end %}
        {% for step in 1...register_count %}
          {% index = register_count - step %}
          {% lines << "valignq $$7, %#{carries[index - 1].id}, %#{carries[index].id}, %#{carries[index].id}" %}
        {% end %}
        {% lines << "valignq $$7, %zmm0, %#{carries[0].id}, %#{carries[0].id}" %}
        {% for index in 0...register_count %}
          {% lines << "vpandq %zmm25, %#{sums[index].id}, %#{sums[index].id}" %}
          {% lines << "vpaddq %#{carries[index].id}, %#{sums[index].id}, %#{sums[index].id}" %}
        {% end %}
        {% for word in 0...mask_word_count %}
          {% lines << "xor %#{greater[word].id}, %#{greater[word].id}" %}
          {% lines << "xor %#{equal[word].id}, %#{equal[word].id}" %}
        {% end %}
        {% for index in 0...register_count %}
          {%
            lines << "vpcmpuq $$6, %zmm25, %#{sums[index].id}, %k2"
            lines << "kmovb %k2, %eax"
            lines << "shl $$#{8 * (index % 8)}, %rax"
            lines << "or %rax, %#{greater[index // 8].id}"
            lines << "vpcmpuq $$0, %zmm25, %#{sums[index].id}, %k2"
            lines << "kmovb %k2, %eax"
            lines << "shl $$#{8 * (index % 8)}, %rax"
            lines << "or %rax, %#{equal[index // 8].id}"
          %}
        {% end %}
        # Lanes that take a carry: ((greater << 1) + equal) ^ equal, over
        # all the mask words as one number.
        {% for word in 0...mask_word_count %}
          {% lines << "#{(word == 0 ? "add" : "adc").id} %#{greater[word].id}, %#{greater[word].id}" %}
        {% end %}
        {% for word in 0...mask_word_count %}
          {% lines << "#{(word == 0 ? "add" : "adc").id} %#{equal[word].id}, %#{greater[word].id}" %}
        {% end %}
        {% for word in 0...mask_word_count %}
          {% lines << "xor %#{equal[word].id}, %#{greater[word].id}" %}
        {% end %}
        {% for index in 0...register_count %}
          {%
            lines << "mov %#{greater[index // 8].id}, %rax"
            lines << "shr $$#{8 * (index % 8)}, %rax"
            lines << "kmovb %eax, %k2"
            lines << "vpsubq %zmm25, %#{sums[index].id}, %#{sums[index].id}{%k2}"
            lines << "vpandq %zmm25, %#{sums[index].id}, %#{sums[index].id}"
          %}
        {% end %}
      {% end %}
      {% for half in halves %}
        {% for index in 0...register_count %}
          {% lines << "vmovdqu64 %#{half[:sums][index].id}, #{half[:offset] + 64 * index}(%rbx)" %}
        {% end %}
      {% end %}
      {% lines << "vzeroupper" %}
      %finished = 0_u64
      asm({{ lines.join("\n") }}
        : "=r"(%finished) : "0"({{ parameters }})
        : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "r8", "r9", "r10", "r11", "r12", "r13", "r14",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "xmm11",
          "xmm12", "xmm13", "xmm14", "xmm15", "memory", "flags")
    end

    # The text that copies entry $0[2] (for the first number) and entry
    # $0[3] (for the second) of a table of 32 entries, each two numbers of
    # *padded_digit_count* lanes, into the two numbers at $0[0]; $0[1]
    # points at the table. Every entry is read, and each register of the
    # wanted entry is kept by a blend under the mask of lanes where the
    # entry's number (counted up in zmm3) equals the index.
    macro dual_select_statement(padded_digit_count, parameters)
      {%
        register_count = padded_digit_count // 8
        entry_bytesize = 16 * padded_digit_count
        lines = [] of StringLiteral
        lines << "mov 0($0), %rdi"
        lines << "mov 8($0), %rsi"
        lines << "vpbroadcastq 16($0), %zmm1"
        lines << "vpbroadcastq 24($0), %zmm2"
        lines << "vpxorq %zmm3, %zmm3, %zmm3"
        lines << "mov $$1, %rax"
        lines << "vpbroadcastq %rax, %zmm4"
      %}
      {% for index in 0...(2 * register_count) %}
        {% lines << "vpxorq %zmm#{5 + index}, %zmm#{5 + index}, %zmm#{5 + index}" %}
      {% end %}
      {% for entry in 0...32 %}
        {%
          lines << "vpcmpeqq %zmm3, %zmm1, %k1"
          lines << "vpcmpeqq %zmm3, %zmm2, %k2"
        %}
        {% for index in 0...(2 * register_count) %}
          {% mask = index < register_count ? "k1" : "k2" %}
          {% lines << "vpblendmq #{entry * entry_bytesize + 64 * index}(%rsi), %zmm#{5 + index}, %zmm#{5 + index}{%#{mask.id}}" %}
        {% end %}
        {% lines << "vpaddq %zmm4, %zmm3, %zmm3" %}
      {% end %}
      {% for index in 0...(2 * register_count) %}
        {% lines << "vmovdqu64 %zmm#{5 + index}, #{64 * index}(%rdi)" %}
      {% end %}
      {% lines << "vzeroupper" %}
      %finished = 0_u64
      asm({{ lines.join("\n") }}
        : "=r"(%finished) : "0"({{ parameters }})
        : "rax", "rsi", "rdi", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10",
          "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "flags")
    end

    {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
      {% for word_count in SUPPORTED_WORD_COUNTS %}
        {% digit_count = (64 * word_count + 51) // 52 %}
        {% padded_digit_count = (digit_count + 7) // 8 * 8 %}
        # Two almost Montgomery multiplications of numbers of
        # {{ digit_count }} digits ({{ padded_digit_count }} lanes each),
        # one for each half of the operands; *result* may be *a* or *b*.
        def self.dual_multiply_{{ word_count }}(result : UInt64*, a : UInt64*, b : UInt64*, modulus : UInt64*,
                                                first_negated_inverse : UInt64, second_negated_inverse : UInt64) : Nil
          operands = StaticArray[result.address, a.address, b.address, modulus.address, first_negated_inverse,
                                 second_negated_inverse]
          operands_address = operands.to_unsafe.address
          multiplication_statement(2, {{ digit_count }}, {{ padded_digit_count }}, operands_address)
        end

        # Two almost Montgomery squarings of numbers of {{ digit_count }}
        # digits, as `dual_multiply_{{ word_count }}` with *a* for *b*, but
        # each product a_i·a_j with i < j taken once, against the digits of
        # 2a, which it writes to *doubled* (as many words as *a*); *result*
        # may be *a*.
        def self.dual_square_{{ word_count }}(result : UInt64*, a : UInt64*, modulus : UInt64*, doubled : UInt64*,
                                              first_negated_inverse : UInt64, second_negated_inverse : UInt64) : Nil
          operands = StaticArray[result.address, a.address, doubled.address, modulus.address, first_negated_inverse,
                                 second_negated_inverse]
          operands_address = operands.to_unsafe.address
          multiplication_statement(2, {{ digit_count }}, {{ padded_digit_count }}, operands_address, true)
        end

        # Copies entry *first_index* of the table's first numbers and entry
        # *second_index* of its second numbers (both below 32, secret) into
        # *destination*, reading every entry.
        def self.dual_select_{{ word_count }}(destination : UInt64*, table : UInt64*, first_index : UInt64, second_index : UInt64) : Nil
          operands = StaticArray[destination.address, table.address, first_index, second_index]
          operands_address = operands.to_unsafe.address
          dual_select_statement({{ padded_digit_count }}, operands_address)
        end
      {% end %}

      {% for word_count in PUBLIC_WORD_COUNTS %}
        {% digit_count = (64 * word_count + 51) // 52 %}
        {% padded_digit_count = (digit_count + 7) // 8 * 8 %}
        # One almost Montgomery multiplication of numbers of
        # {{ digit_count }} digits ({{ padded_digit_count }} lanes); *result*
        # may be *a* or *b*.
        def self.multiply_{{ word_count }}(result : UInt64*, a : UInt64*, b : UInt64*, modulus : UInt64*, negated_inverse : UInt64) : Nil
          operands = StaticArray[result.address, a.address, b.address, modulus.address, negated_inverse, 0_u64]
          operands_address = operands.to_unsafe.address
          multiplication_statement(1, {{ digit_count }}, {{ padded_digit_count }}, operands_address)
        end
      {% end %}
    {% end %}

    # Writes the words of *words* (little-endian) into *digits* as 52-bit
    # digits, the highest digits zero. The shifts and indices depend only on
    # the sizes.
    def self.write_digits(words : Slice(UInt64), digits : Slice(UInt64)) : Nil
      digits.size.times do |digit_index|
        low_bit = DIGIT_BIT_COUNT * digit_index
        word_index = low_bit // 64
        shift = low_bit % 64
        value = word_index < words.size ? words[word_index] >> shift : 0_u64
        if shift > 64 - DIGIT_BIT_COUNT && word_index + 1 < words.size
          value |= words[word_index + 1] << (64 - shift)
        end
        digits[digit_index] = value & DIGIT_MASK
      end
    end

    # Writes the 52-bit *digits* into *words*; bits above what *words* holds
    # are dropped.
    def self.write_words(digits : Slice(UInt64), words : Slice(UInt64)) : Nil
      words.fill(0_u64)
      digits.size.times do |digit_index|
        low_bit = DIGIT_BIT_COUNT * digit_index
        word_index = low_bit // 64
        shift = low_bit % 64
        words[word_index] |= digits[digit_index] << shift if word_index < words.size
        if shift > 64 - DIGIT_BIT_COUNT && word_index + 1 < words.size
          words[word_index + 1] |= digits[digit_index] >> (64 - shift)
        end
      end
    end

    # The two primes of a key in the form this path works on, with the
    # constants of its Montgomery arithmetic, and the dual exponentiation.
    # Built only where `usable_for?` says so. Every value here is secret
    # except the sizes. A struct, as `OddModulus` is, so that a key holds it
    # in place and reads its sizes at fixed offsets.
    struct PrimePair
      @word_count : Int32
      @padded_digit_count : Int32
      @first_prime : Slice(UInt64)
      @second_prime : Slice(UInt64)
      @first_negated_inverse : UInt64
      @second_negated_inverse : UInt64
      # Each of these is two numbers of `@padded_digit_count` digits, the
      # first prime's then the second's: the primes; R' mod p (one, in
      # Montgomery form with R'); R'²/R mod p, which takes a number from
      # Montgomery form with R = 2^(64n) to Montgomery form with
      # R' = 2^(52d); and the factors the exponentiation ends with: R mod p
      # for the first prime (its result goes on in Montgomery form with R)
      # and 1 for the second (its result leaves Montgomery form).
      @moduli : Slice(UInt64)
      @ones : Slice(UInt64)
      @conversions : Slice(UInt64)
      @final_factors : Slice(UInt64)

      # Whether the processor has IFMA and the two primes, of
      # *first_word_count* and *second_word_count* words, with exponents of
      # *first_exponent_bytesize* and *second_exponent_bytesize* bytes, suit
      # this path. All of these are public.
      def self.usable_for?(first_word_count : Int32, second_word_count : Int32, first_exponent_bytesize : Int32,
                           second_exponent_bytesize : Int32) : Bool
        {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
          ProcessorFeatures::HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD && first_word_count == second_word_count &&
            SUPPORTED_WORD_COUNTS.includes?(first_word_count) && first_exponent_bytesize == second_exponent_bytesize
        {% else %}
          false
        {% end %}
      end

      # Takes each prime's words, R² mod p (with R = 2^(64n)) and
      # -p^-1 mod 2^64. The constants are found by Montgomery multiplication
      # and doubling, in time that depends only on the sizes.
      def initialize(@first_prime : Slice(UInt64), first_r_squared : Slice(UInt64), @first_negated_inverse : UInt64,
                     @second_prime : Slice(UInt64), second_r_squared : Slice(UInt64), @second_negated_inverse : UInt64)
        @word_count = @first_prime.size
        @padded_digit_count = MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.padded_digit_count_for(@word_count)
        pair_size = 2 * @padded_digit_count
        @moduli = Slice(UInt64).new(pair_size)
        @ones = Slice(UInt64).new(pair_size)
        @conversions = Slice(UInt64).new(pair_size)
        @final_factors = Slice(UInt64).new(pair_size)
        extra_bit_count = DIGIT_BIT_COUNT * MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.digit_count_for(@word_count) -
                          64 * @word_count
        scratch = Slice(UInt64).new(MontgomeryArithmetic.multiplication_scratch_word_count(@word_count))
        r_modulo_prime = Slice(UInt64).new(@word_count)
        one = Slice(UInt64).new(@word_count)
        one[0] = 1_u64
        {
          {@first_prime, first_r_squared, @first_negated_inverse},
          {@second_prime, second_r_squared, @second_negated_inverse},
        }.each_with_index do |(prime, r_squared, negated_inverse), half|
          offset = half * @padded_digit_count
          MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(prime, @moduli[offset, @padded_digit_count])
          MontgomeryArithmetic.multiply(r_modulo_prime, one, r_squared, prime, negated_inverse, scratch)
          if half == 0
            MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(r_modulo_prime, @final_factors[offset, @padded_digit_count])
          else
            @final_factors[offset] = 1_u64
          end
          # R' = R·2^extra, and R'²/R = R·2^(2·extra).
          extra_bit_count.times { MontgomeryArithmetic.double(r_modulo_prime, prime, scratch) }
          MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(r_modulo_prime, @ones[offset, @padded_digit_count])
          extra_bit_count.times { MontgomeryArithmetic.double(r_modulo_prime, prime, scratch) }
          MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(r_modulo_prime, @conversions[offset, @padded_digit_count])
        end
        wipe_words(r_modulo_prime)
        wipe_words(scratch)
      end

      # Sets *first_result* to the Montgomery form (with R = 2^(64n)) of
      # base^exponent mod p, and *second_result* to base^exponent mod q, each
      # base given in Montgomery form with R and below its prime, by fixed
      # five-bit windows over both exponents at once. Constant time.
      def exponentiate(first_result : Slice(UInt64), second_result : Slice(UInt64), first_base : Slice(UInt64),
                       second_base : Slice(UInt64), first_exponent : Bytes, second_exponent : Bytes) : Nil
        pair_size = 2 * @padded_digit_count
        table = Slice(UInt64).new(MontgomeryArithmetic::TABLE_ENTRY_COUNT * pair_size)
        power = Slice(UInt64).new(pair_size)
        selected = Slice(UInt64).new(pair_size)
        doubled = Slice(UInt64).new(pair_size)
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(first_base, selected[0, @padded_digit_count])
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(second_base, selected[@padded_digit_count, @padded_digit_count])
        @ones.copy_to(table[0, pair_size])
        multiply_pair(table[pair_size, pair_size], selected, @conversions)
        (2...MontgomeryArithmetic::TABLE_ENTRY_COUNT).each do |entry|
          if entry.even?
            half_entry = table[(entry // 2) * pair_size, pair_size]
            square_pair(table[entry * pair_size, pair_size], half_entry, doubled)
          else
            multiply_pair(table[entry * pair_size, pair_size], table[(entry - 1) * pair_size, pair_size], table[pair_size, pair_size])
          end
        end

        @ones.copy_to(power)
        bit_count = first_exponent.size * 8
        window_count = (bit_count + MontgomeryArithmetic::WINDOW_BIT_COUNT - 1) // MontgomeryArithmetic::WINDOW_BIT_COUNT
        (window_count - 1).downto(0) do |window_index|
          MontgomeryArithmetic::WINDOW_BIT_COUNT.times { square_pair(power, power, doubled) }
          low_bit = window_index * MontgomeryArithmetic::WINDOW_BIT_COUNT
          select_pair(selected, table, MontgomeryArithmetic.window_bits(first_exponent, low_bit),
            MontgomeryArithmetic.window_bits(second_exponent, low_bit))
          multiply_pair(power, power, selected)
        end
        multiply_pair(power, power, @final_factors)

        # Each result is below twice its prime: one subtraction, kept or
        # dropped by mask, reduces it.
        unreduced = Slice(UInt64).new(@word_count)
        first_digits = power[0, @padded_digit_count]
        second_digits = power[@padded_digit_count, @padded_digit_count]
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_words(first_digits, unreduced)
        MontgomeryArithmetic.subtract_modulus_when_not_below(first_result, unreduced, top_bit_of(first_digits), @first_prime)
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_words(second_digits, unreduced)
        MontgomeryArithmetic.subtract_modulus_when_not_below(second_result, unreduced, top_bit_of(second_digits), @second_prime)
        {table, power, selected, doubled, unreduced}.each { |words| wipe_words(words) }
      end

      # The bit of the number in *digits* at 2^(64n), just above its n
      # words, which a result below twice the prime may have.
      private def top_bit_of(digits : Slice(UInt64)) : UInt64
        bit = 64 * @word_count
        (digits[bit // DIGIT_BIT_COUNT] >> (bit % DIGIT_BIT_COUNT)) & 1_u64
      end

      private def multiply_pair(result : Slice(UInt64), a : Slice(UInt64), b : Slice(UInt64)) : Nil
        {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
          {% begin %}
            case @word_count
            {% for word_count in SUPPORTED_WORD_COUNTS %}
            when {{ word_count }}
              MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.dual_multiply_{{ word_count }}(result.to_unsafe, a.to_unsafe,
                b.to_unsafe, @moduli.to_unsafe, @first_negated_inverse, @second_negated_inverse)
            {% end %}
            end
          {% end %}
        {% end %}
      end

      # Squares both numbers of *a* into *result*, with *doubled* (a pair's
      # size) for the digits of 2a. At 16 words (20 digits) on a processor
      # that splits 512-bit operations, building the squaring's diagonal
      # costs about what it saves, and the multiplication is as fast.
      private def square_pair(result : Slice(UInt64), a : Slice(UInt64), doubled : Slice(UInt64)) : Nil
        return multiply_pair(result, a, a) if @word_count == 16 && ProcessorFeatures::SPLITS_512_BIT_OPERATIONS

        {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
          {% begin %}
            case @word_count
            {% for word_count in SUPPORTED_WORD_COUNTS %}
            when {{ word_count }}
              MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.dual_square_{{ word_count }}(result.to_unsafe, a.to_unsafe,
                @moduli.to_unsafe, doubled.to_unsafe, @first_negated_inverse, @second_negated_inverse)
            {% end %}
            end
          {% end %}
        {% end %}
      end

      private def select_pair(destination : Slice(UInt64), table : Slice(UInt64), first_index : UInt64, second_index : UInt64) : Nil
        {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
          {% begin %}
            case @word_count
            {% for word_count in SUPPORTED_WORD_COUNTS %}
            when {{ word_count }}
              MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.dual_select_{{ word_count }}(destination.to_unsafe, table.to_unsafe,
                first_index, second_index)
            {% end %}
            end
          {% end %}
        {% end %}
      end

      # Overwrites the constants; the primes' words belong to the key, which
      # wipes them.
      def wipe : Nil
        {@moduli, @ones, @conversions, @final_factors}.each { |words| wipe_words(words) }
      end

      private def wipe_words(words : Slice(UInt64)) : Nil
        SecretWiping.wipe(Bytes.new(words.to_unsafe.as(UInt8*), words.size * 8))
      end
    end

    # A modulus in the form this path works on, for the public operation
    # (raising to the public exponent e): the modulus in digits, -n^-1
    # mod 2^64, and R'^e mod n. Built only where `usable_for?` says so. A
    # struct, as `OddModulus` is, so that a key holds it in place and reads
    # its sizes at fixed offsets.
    struct PublicModulus
      @word_count : Int32
      @padded_digit_count : Int32
      @exponent : UInt64
      @modulus : Slice(UInt64)
      @negated_inverse : UInt64
      @digits : Slice(UInt64)
      @correction : Slice(UInt64)

      # Whether the processor has IFMA and a modulus of *word_count* words
      # suits this path. Public.
      def self.usable_for?(word_count : Int32) : Bool
        {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
          ProcessorFeatures::HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD && PUBLIC_WORD_COUNTS.includes?(word_count)
        {% else %}
          false
        {% end %}
      end

      # Takes the modulus's words, R² mod n (with R = 2^(64n)), -n^-1
      # mod 2^64 and the public exponent. R'^e mod n is found with the
      # 64-bit arithmetic: R' mod n by doubling R mod n, then its power.
      def initialize(@modulus : Slice(UInt64), r_squared : Slice(UInt64), @negated_inverse : UInt64, @exponent : UInt64)
        @word_count = @modulus.size
        @padded_digit_count = MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.padded_digit_count_for(@word_count)
        @digits = Slice(UInt64).new(@padded_digit_count)
        @correction = Slice(UInt64).new(@padded_digit_count)
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(@modulus, @digits)
        scratch = Slice(UInt64).new(MontgomeryArithmetic.public_exponentiation_scratch_word_count(@word_count))
        r_modulo_modulus = Slice(UInt64).new(@word_count)
        one = Slice(UInt64).new(@word_count)
        one[0] = 1_u64
        MontgomeryArithmetic.multiply(r_modulo_modulus, one, r_squared, @modulus, @negated_inverse,
          scratch[0, MontgomeryArithmetic.multiplication_scratch_word_count(@word_count)])
        extra_bit_count = DIGIT_BIT_COUNT * MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.digit_count_for(@word_count) -
                          64 * @word_count
        extra_bit_count.times { MontgomeryArithmetic.double(r_modulo_modulus, @modulus, scratch) }
        power = Slice(UInt64).new(@word_count)
        MontgomeryArithmetic.exponentiate_by_public_exponent(power, r_modulo_modulus, @exponent, @modulus, r_squared,
          @negated_inverse, scratch)
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(power, @correction)
      end

      # Sets *result* to base^e mod n, for a *base* below n: left to right
      # square and multiply on the plain base, whose almost Montgomery
      # products keep the form x^k/R'^(k-1), then one product with R'^e.
      # The time depends on the exponent's bits, which are public, and not
      # on the base.
      def exponentiate(result : Slice(UInt64), base : Slice(UInt64)) : Nil
        plain_base = Slice(UInt64).new(@padded_digit_count)
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_digits(base, plain_base)
        power = plain_base.dup
        highest_bit = 63 - @exponent.leading_zeros_count
        (highest_bit - 1).downto(0) do |bit_position|
          multiply(power, power, power)
          multiply(power, power, plain_base) if (@exponent >> bit_position) & 1_u64 == 1_u64
        end
        multiply(power, power, @correction)
        # Below 2n: one subtraction, kept or dropped by mask, reduces it.
        unreduced = Slice(UInt64).new(@word_count)
        MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.write_words(power, unreduced)
        bit = 64 * @word_count
        top_bit = (power[bit // DIGIT_BIT_COUNT] >> (bit % DIGIT_BIT_COUNT)) & 1_u64
        MontgomeryArithmetic.subtract_modulus_when_not_below(result, unreduced, top_bit, @modulus)
        {plain_base, power, unreduced}.each { |words| SecretWiping.wipe(Bytes.new(words.to_unsafe.as(UInt8*), words.size * 8)) }
      end

      private def multiply(result : Slice(UInt64), a : Slice(UInt64), b : Slice(UInt64)) : Nil
        {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) %}
          {% begin %}
            case @word_count
            {% for word_count in PUBLIC_WORD_COUNTS %}
            when {{ word_count }}
              MontgomeryMultiplicationWithIntegerFusedMultiplyAdd.multiply_{{ word_count }}(result.to_unsafe, a.to_unsafe,
                b.to_unsafe, @digits.to_unsafe, @negated_inverse)
            {% end %}
            end
          {% end %}
        {% end %}
      end
    end
  end
end
