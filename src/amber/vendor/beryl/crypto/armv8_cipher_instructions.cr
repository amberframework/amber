module Amber::Beryl::Crypto
  # :nodoc:
  #
  # AES, GHASH and ChaCha20 written with the instructions of ARMv8
  # processors: `aese`, `aesmc`, `aesd` and `aesimc` for AES, `pmull` and
  # `pmull2` (carry-less multiplication) for GHASH, and the Advanced SIMD
  # instructions for ChaCha20 (Arm Architecture Reference Manual C7.2). Each
  # macro expands, at its call site, to one block of assembly that works on
  # whole blocks; the callers in `V1::GaloisCounterModeWithProcessorInstructions`,
  # `V1::ChaCha20WithVectorInstructions` and
  # `Compatibility::CipherBlockChainingWithProcessorInstructions` handle the
  # partial blocks and choose the round count.
  #
  # Crystal has no vector types, so the instructions cannot be reached as
  # LLVM intrinsics; the assembly is written out here instead, as in
  # `Armv8HashInstructions`. Every statement has at most one branch, which
  # closes its loop on the count of groups left, and reads and writes memory
  # only at fixed offsets from its inputs, so its timing depends on the sizes
  # it is given and on nothing a key or a message holds.
  # `scripts/check_secret_flow.rb` checks exactly that. The AES and
  # carry-less multiply instructions take the same time whatever their
  # operands hold, which is why they replace the bitsliced AES and the
  # integer-multiply GHASH where the processor has them.
  #
  # GHASH works on blocks with their bytes reversed, so that the field's
  # bit order matches the processor's, and on hash key powers that were
  # multiplied by x once ("twisted") when they were prepared, which absorbs
  # the one-bit shift a reflected product needs. The reduction modulo
  # x^128 + x^7 + x^2 + x + 1 takes two carry-less multiplies by the
  # constant 0xc2 << 56. This is the method of Gueron and Kounavis, "Intel
  # Carry-Less Multiplication Instruction and its Usage for Computing the GCM
  # Mode" (2014), in the arrangement OpenSSL's `ghashv8-armx` uses; the
  # vectors and the differential against libcrypto check it.
  module Armv8CipherInstructions
    # Bytes in one table entry of hash key powers: the twisted power, then
    # the same power with its two 64-bit halves swapped. With both, the four
    # products of a block and a power are one carry-less multiply each.
    HASH_KEY_POWER_BYTESIZE = 32

    # Powers of the hash key kept: H to H^16, one per block of a group.
    HASH_KEY_POWER_COUNT = 16

    # Prepares the table of hash key powers at *hash_key_powers*
    # (`HASH_KEY_POWER_COUNT` entries of `HASH_KEY_POWER_BYTESIZE` bytes) from
    # the hash key at *hash_key* (16 bytes, the encryption of the zero
    # block). The highest power comes first: entry j holds H^(16 - j), so
    # that n blocks hashed together take the n entries from 16 - n on. No
    # loop: fifteen multiplies written out.
    macro prepare_hash_key_powers(hash_key, hash_key_powers)
      {% template = "
  .arch_extension aes
  mov x9, $0
  mov x10, $1
  ld1 {v17.16b}, [x9]
  rev64 v17.16b, v17.16b
  ext v3.16b, v17.16b, v17.16b, #8
  movi v19.16b, #0xe1
  shl v19.2d, v19.2d, #57
  ushr v18.2d, v19.2d, #63
  dup v17.4s, v17.s[1]
  ext v16.16b, v18.16b, v19.16b, #8
  ushr v18.2d, v3.2d, #63
  sshr v17.4s, v17.4s, #31
  and v18.16b, v18.16b, v16.16b
  shl v3.2d, v3.2d, #1
  ext v18.16b, v18.16b, v18.16b, #8
  and v16.16b, v16.16b, v17.16b
  orr v3.16b, v3.16b, v18.16b
  eor v20.16b, v3.16b, v16.16b
  ext v21.16b, v20.16b, v20.16b, #8
  stp q20, q21, [x10, #480]
  eor v21.16b, v21.16b, v20.16b
  mov v22.16b, v20.16b
" %}
      {% for power in 2..16 %}
        {% template = template + "
  pmull v0.1q, v22.1d, v20.1d
  pmull2 v2.1q, v22.2d, v20.2d
  ext v4.16b, v22.16b, v22.16b, #8
  eor v4.16b, v4.16b, v22.16b
  pmull v1.1q, v4.1d, v21.1d
  ext v5.16b, v0.16b, v2.16b, #8
  eor v6.16b, v0.16b, v2.16b
  eor v1.16b, v1.16b, v5.16b
  eor v1.16b, v1.16b, v6.16b
  pmull v6.1q, v0.1d, v19.1d
  mov v2.d[0], v1.d[1]
  mov v1.d[1], v0.d[0]
  eor v0.16b, v1.16b, v6.16b
  ext v6.16b, v0.16b, v0.16b, #8
  pmull v0.1q, v0.1d, v19.1d
  eor v6.16b, v6.16b, v2.16b
  eor v22.16b, v0.16b, v6.16b
  ext v23.16b, v22.16b, v22.16b, #8
  stp q22, q23, [x10, ##{(16 - power) * 32}]
" %}
      {% end %}
      asm({{ template }} :: "r"({{ hash_key }}), "r"({{ hash_key_powers }}) : "x9", "x10", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "memory")
    end

    # Counter mode: XORs the AES keystream of the counter block at
    # *counter_block* into whole blocks at *input* and writes them to
    # *output*. The last four bytes of the counter block count up as a
    # big-endian number that wraps at 2^32, and the counter block left behind
    # is the next one. *round_count* (10, 12 or 14) names how many of the
    # round keys at *round_keys* are used. *has_three_way_exclusive_or*: the
    # processor has `eor3` (the SHA3 extension), which XORs three registers
    # in one instruction.
    #
    # - *is_pipelined* false: *group_count* (at least 1) single blocks, one
    #   per pass.
    # - *is_pipelined* true: 2 * *group_count* + 1 groups of eight blocks
    #   (*group_count* at least 1), software pipelined. Two sets of eight
    #   registers take turns: while one set runs the second half of its
    #   rounds and is written out, the other starts the first half of its
    #   rounds on the next counters, and the two are interleaved round by
    #   round. The processor then always has independent AES instructions to
    #   start, where a group that runs all its rounds before the next group
    #   starts leaves it waiting on each round's latency. The first group
    #   starts before the loop and the last one finishes after it.
    #
    # Registers: x9 round keys, x10 counter block, x11 passes left, x12
    # input, x13 output, x16 and x17 the counter; v0 to v15 the blocks, v16
    # to v30 the round keys, v31 a message block. A counter block is the
    # stored block with its last word replaced. `aese` and `aesmc` stay side
    # by side so that the processor can fuse them.
    macro encrypt_counter_blocks(round_keys, counter_block, input, output, group_count, round_count, is_pipelined,
                                 has_three_way_exclusive_or)
      {% key_count = round_count + 1 %}
      {% template = "  .arch_extension sha3\n  .arch_extension aes\n  mov x9, $0\n  mov x10, $1\n  mov x12, $2\n  mov x13, $3\n  mov x11, $4\n" %}
      {% for start in [0, 4, 8, 12] %}
        {% if start < key_count %}
          {% count = key_count - start %}
          {% if count > 4 %}{% count = 4 %}{% end %}
          {% registers = [] of StringLiteral %}
          {% for offset in 0...count %}{% registers << "v#{16 + start + offset}.16b" %}{% end %}
          {% template = template + "  ld1 {#{registers.join(", ").id}}, [x9], ##{count * 16}\n" %}
        {% end %}
      {% end %}
      {% template = template + "  ldr w16, [x10, #12]\n  rev w16, w16\n" %}

      {% if is_pipelined %}
        # For each set of eight registers (from v0 and from v8): the lines
        # that load its counter blocks, its rounds before the split, and its
        # rounds after the split with the final round, the message XOR and
        # the stores.
        {% split = round_count // 2 %}
        {% list_of_counter_lines = {} of NumberLiteral => ArrayLiteral %}
        {% list_of_early_rounds = {} of NumberLiteral => ArrayLiteral %}
        {% list_of_late_rounds = {} of NumberLiteral => ArrayLiteral %}
        {% for base in [0, 8] %}
          {% lines = [] of StringLiteral %}
          {% for block in 0...8 %}
            {% lines << "  add w17, w16, ##{block}\n  rev w17, w17\n  ldr q#{base + block}, [x10]\n  mov v#{base + block}.s[3], w17" %}
          {% end %}
          {% lines << "  add w16, w16, #8" %}
          {% list_of_counter_lines[base] = lines %}
          {% rounds = [] of ArrayLiteral %}
          {% for round in 0...split %}
            {% lines = [] of StringLiteral %}
            {% for block in 0...8 %}
              {% lines << "  aese v#{base + block}.16b, v#{16 + round}.16b\n  aesmc v#{base + block}.16b, v#{base + block}.16b" %}
            {% end %}
            {% rounds << lines %}
          {% end %}
          {% list_of_early_rounds[base] = rounds %}
          {% rounds = [] of ArrayLiteral %}
          {% for round in split...(round_count - 1) %}
            {% lines = [] of StringLiteral %}
            {% for block in 0...8 %}
              {% lines << "  aese v#{base + block}.16b, v#{16 + round}.16b\n  aesmc v#{base + block}.16b, v#{base + block}.16b" %}
            {% end %}
            {% rounds << lines %}
          {% end %}
          {% lines = [] of StringLiteral %}
          {% for block in 0...8 %}
            {% line = "  aese v#{base + block}.16b, v#{16 + round_count - 1}.16b\n  ldr q31, [x12, ##{block * 16}]\n" %}
            {% if has_three_way_exclusive_or %}
              {% line = line + "  eor3 v#{base + block}.16b, v#{base + block}.16b, v#{16 + round_count}.16b, v31.16b" %}
            {% else %}
              {% line = line + "  eor v#{base + block}.16b, v#{base + block}.16b, v#{16 + round_count}.16b\n  eor v#{base + block}.16b, v#{base + block}.16b, v31.16b" %}
            {% end %}
            {% lines << line %}
          {% end %}
          {% lines << "  st1 {v#{base}.16b, v#{base + 1}.16b, v#{base + 2}.16b, v#{base + 3}.16b}, [x13], #64\n  st1 {v#{base + 4}.16b, v#{base + 5}.16b, v#{base + 6}.16b, v#{base + 7}.16b}, [x13], #64\n  add x12, x12, #128" %}
          {% rounds << lines %}
          {% list_of_late_rounds[base] = rounds %}
        {% end %}

        {% template = template + list_of_counter_lines[0].join("\n") + "\n" %}
        {% for lines in list_of_early_rounds[0] %}
          {% template = template + lines.join("\n") + "\n" %}
        {% end %}
        {% template = template + "1:\n" %}
        {% for roles in [[0, 8], [8, 0]] %}
          {% finishing = roles[0] %}
          {% starting = roles[1] %}
          {% template = template + list_of_counter_lines[starting].join("\n") + "\n" %}
          {% step_count = list_of_late_rounds[finishing].size %}
          {% if list_of_early_rounds[starting].size > step_count %}
            {% step_count = list_of_early_rounds[starting].size %}
          {% end %}
          {% for step in 0...step_count %}
            {% late_lines = list_of_late_rounds[finishing][step] %}
            {% early_lines = list_of_early_rounds[starting][step] %}
            {% for index in 0...9 %}
              {% if late_lines && late_lines[index] %}
                {% template = template + late_lines[index] + "\n" %}
              {% end %}
              {% if early_lines && early_lines[index] %}
                {% template = template + early_lines[index] + "\n" %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
        {% template = template + "  subs x11, x11, #1\n  b.ne 1b\n" %}
        {% for lines in list_of_late_rounds[0] %}
          {% template = template + lines.join("\n") + "\n" %}
        {% end %}
      {% else %}
        {% template = template + "1:\n  rev w17, w16\n  ldr q0, [x10]\n  mov v0.s[3], w17\n  add w16, w16, #1\n" %}
        {% for round in 0...(round_count - 1) %}
          {% template = template + "  aese v0.16b, v#{16 + round}.16b\n  aesmc v0.16b, v0.16b\n" %}
        {% end %}
        {% template = template + "  aese v0.16b, v#{16 + round_count - 1}.16b\n  ld1 {v31.16b}, [x12], #16\n" %}
        {% if has_three_way_exclusive_or %}
          {% template = template + "  eor3 v0.16b, v0.16b, v#{16 + round_count}.16b, v31.16b\n" %}
        {% else %}
          {% template = template + "  eor v0.16b, v0.16b, v#{16 + round_count}.16b\n  eor v0.16b, v0.16b, v31.16b\n" %}
        {% end %}
        {% template = template + "  st1 {v0.16b}, [x13], #16\n  subs x11, x11, #1\n  b.ne 1b\n" %}
      {% end %}
      {% template = template + "  rev w16, w16\n  str w16, [x10, #12]\n" %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ counter_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }})
        : "x9", "x10", "x11", "x12", "x13", "x16", "x17",
          "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15",
          "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30", "v31",
          "memory", "cc")
    end

    # GHASH: mixes whole blocks at *input* into the accumulator at
    # *accumulator* (16 bytes, byte-reversed) with the hash key powers that
    # start at *first_hash_key_power*.
    #
    # - *blocks_per_group* 16: *group_count* groups of sixteen blocks, each
    #   multiplied by H^16 to H (the table from its first entry) and reduced
    #   once.
    # - *blocks_per_group* 1: *group_count* blocks (at most 16), multiplied
    #   by the powers from the entry *first_hash_key_power* points at on,
    #   summed, and reduced once at the end. The accumulator joins the first
    #   block only: v30 holds it for the first pass and zero after.
    #
    # A block is hashed as four carry-less multiplies of its byte-reversed
    # value by a power and by the same power with its halves swapped; the
    # sums of the low (v24), middle (v25) and high (v26) products are reduced
    # once, by moving the middle sum onto the product's middle words and
    # folding the upper half down with two multiplies by 0xc2 << 56 (v29).
    # In a group of sixteen, blocks 0 and 1 are hashed last: block 0 alone
    # waits for the accumulator, so the other products are ready by then.
    #
    # Registers: x8 hash key powers, x11 groups left, x12 input, x7 the
    # accumulator; v0 to v15 the blocks, v16 to v23 powers and products, v31
    # the accumulator.
    macro absorb_hash_blocks(accumulator, first_hash_key_power, input, group_count, blocks_per_group, has_three_way_exclusive_or)
      {% template = "  .arch_extension sha3\n  .arch_extension aes\n  mov x7, $0\n  mov x8, $1\n  mov x12, $2\n  mov x11, $3\n  ld1 {v31.16b}, [x7]\n  movi v29.16b, #0xe1\n  shl v29.2d, v29.2d, #57\n" %}
      {% if blocks_per_group == 16 %}
        {% template = template + "1:\n" %}
        {% for start in [0, 4, 8, 12] %}
          {% template = template + "  ld1 {v#{start}.16b, v#{start + 1}.16b, v#{start + 2}.16b, v#{start + 3}.16b}, [x12], #64\n" %}
        {% end %}
        {% for pair in [1, 2, 3, 4, 5, 6, 7, 0] %}
          {% first = pair * 2 %}
          {% second = pair * 2 + 1 %}
          {% template = template + "  rev64 v#{first}.16b, v#{first}.16b\n  rev64 v#{second}.16b, v#{second}.16b\n" %}
          {% if pair == 0 %}
            {% template = template + "  ext v23.16b, v31.16b, v31.16b, #8\n  eor v0.16b, v0.16b, v23.16b\n" %}
          {% end %}
          {% template = template + "  ldp q16, q17, [x8, ##{first * 32}]\n  ldp q18, q19, [x8, ##{second * 32}]
  pmull v20.1q, v#{first}.1d, v17.1d
  pmull2 v17.1q, v#{first}.2d, v17.2d
  pmull v21.1q, v#{second}.1d, v19.1d
  pmull2 v19.1q, v#{second}.2d, v19.2d
  pmull v22.1q, v#{first}.1d, v16.1d
  pmull2 v16.1q, v#{first}.2d, v16.2d
  pmull v23.1q, v#{second}.1d, v18.1d
  pmull2 v18.1q, v#{second}.2d, v18.2d
" %}
          {% if pair == 1 %}
            {% template = template + "  eor v26.16b, v20.16b, v21.16b\n  eor v24.16b, v17.16b, v19.16b\n  eor v25.16b, v22.16b, v16.16b\n  eor v25.16b, v25.16b, v23.16b\n  eor v25.16b, v25.16b, v18.16b\n" %}
          {% elsif has_three_way_exclusive_or %}
            {% template = template + "  eor3 v26.16b, v26.16b, v20.16b, v21.16b\n  eor3 v24.16b, v24.16b, v17.16b, v19.16b\n  eor3 v25.16b, v25.16b, v22.16b, v16.16b\n  eor3 v25.16b, v25.16b, v23.16b, v18.16b\n" %}
          {% else %}
            {% template = template + "  eor v26.16b, v26.16b, v20.16b\n  eor v26.16b, v26.16b, v21.16b\n  eor v24.16b, v24.16b, v17.16b\n  eor v24.16b, v24.16b, v19.16b\n" %}
            {% template = template + "  eor v25.16b, v25.16b, v22.16b\n  eor v25.16b, v25.16b, v16.16b\n  eor v25.16b, v25.16b, v23.16b\n  eor v25.16b, v25.16b, v18.16b\n" %}
          {% end %}
        {% end %}
      {% else %}
        {% template = template + "  movi v24.16b, #0\n  movi v25.16b, #0\n  movi v26.16b, #0\n  ext v30.16b, v31.16b, v31.16b, #8\n1:
  ld1 {v0.16b}, [x12], #16
  rev64 v0.16b, v0.16b
  eor v0.16b, v0.16b, v30.16b
  movi v30.16b, #0
  ldp q16, q17, [x8], #32
  pmull v20.1q, v0.1d, v17.1d
  pmull2 v17.1q, v0.2d, v17.2d
  pmull v22.1q, v0.1d, v16.1d
  pmull2 v16.1q, v0.2d, v16.2d
  eor v26.16b, v26.16b, v20.16b
  eor v24.16b, v24.16b, v17.16b
" %}
        {% if has_three_way_exclusive_or %}
          {% template = template + "  eor3 v25.16b, v25.16b, v22.16b, v16.16b\n" %}
        {% else %}
          {% template = template + "  eor v25.16b, v25.16b, v22.16b\n  eor v25.16b, v25.16b, v16.16b\n" %}
        {% end %}
        {% template = template + "  subs x11, x11, #1\n  b.ne 1b\n" %}
      {% end %}
      {% template = template + "  ext v20.16b, v24.16b, v26.16b, #8
  eor v25.16b, v25.16b, v20.16b
  pmull v20.1q, v24.1d, v29.1d
  mov v26.d[0], v25.d[1]
  mov v25.d[1], v24.d[0]
  eor v24.16b, v25.16b, v20.16b
  ext v20.16b, v24.16b, v24.16b, #8
  pmull v24.1q, v24.1d, v29.1d
" %}
      {% if has_three_way_exclusive_or %}
        {% template = template + "  eor3 v31.16b, v24.16b, v20.16b, v26.16b\n" %}
      {% else %}
        {% template = template + "  eor v20.16b, v20.16b, v26.16b\n  eor v31.16b, v24.16b, v20.16b\n" %}
      {% end %}
      {% if blocks_per_group == 16 %}
        {% template = template + "  subs x11, x11, #1\n  b.ne 1b\n" %}
      {% end %}
      {% template = template + "  st1 {v31.16b}, [x7]\n" %}
      asm({{ template }} :: "r"({{ accumulator }}), "r"({{ first_hash_key_power }}), "r"({{ input }}), "r"({{ group_count }})
        : "x7", "x8", "x11", "x12",
          "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15",
          "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v29", "v30", "v31",
          "memory", "cc")
    end

    # Writes at *decryption_round_keys* the round keys of the equivalent
    # inverse cipher (FIPS 197 §5.3.5) for the *round_count* rounds of the
    # encryption round keys at *round_keys*: the last key first, the middle
    # keys through `aesimc`, the first key last. No loop.
    macro prepare_decryption_round_keys(round_keys, decryption_round_keys, round_count)
      {% template = "  .arch_extension aes\n  mov x9, $0\n  mov x10, $1\n" %}
      {% for index in 0..round_count %}
        {% template = template + "  ldr q0, [x9, ##{(round_count - index) * 16}]\n" %}
        {% if index > 0 && index < round_count %}
          {% template = template + "  aesimc v0.16b, v0.16b\n" %}
        {% end %}
        {% template = template + "  str q0, [x10, ##{index * 16}]\n" %}
      {% end %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ decryption_round_keys }}) : "x9", "x10", "v0", "memory")
    end

    # CBC encryption (SP 800-38A §6.2) of *block_count* blocks (at least 1),
    # one after the other, since each depends on the last. *chaining_block*
    # holds the initialization vector or the last ciphertext block, and is
    # left holding the last ciphertext block written.
    #
    # The chain from one block to the next is the AES rounds alone: the
    # message block is XORed with the first and the last round key off the
    # chain, and the output of the last `aese` goes straight into the next
    # block's first `aese` (which XORs its operand in first).
    macro encrypt_chained_blocks(round_keys, chaining_block, input, output, block_count, round_count)
      {% key_count = round_count + 1 %}
      {% template = "  .arch_extension aes\n  mov x9, $0\n  mov x10, $1\n  mov x12, $2\n  mov x13, $3\n  mov x11, $4\n" %}
      {% for start in [0, 4, 8, 12] %}
        {% if start < key_count %}
          {% count = key_count - start %}
          {% if count > 4 %}{% count = 4 %}{% end %}
          {% registers = [] of StringLiteral %}
          {% for offset in 0...count %}{% registers << "v#{16 + start + offset}.16b" %}{% end %}
          {% template = template + "  ld1 {#{registers.join(", ").id}}, [x9], ##{count * 16}\n" %}
        {% end %}
      {% end %}
      {% last = 16 + round_count %}
      {% template = template + "  ld1 {v0.16b}, [x10]
  eor v0.16b, v0.16b, v#{last}.16b
  eor v8.16b, v16.16b, v#{last}.16b
1:
  ld1 {v1.16b}, [x12], #16
  eor v1.16b, v1.16b, v8.16b
  aese v0.16b, v1.16b
  aesmc v0.16b, v0.16b
" %}
      {% for round in 1...(round_count - 1) %}
        {% template = template + "  aese v0.16b, v#{16 + round}.16b\n  aesmc v0.16b, v0.16b\n" %}
      {% end %}
      {% template = template + "  aese v0.16b, v#{16 + round_count - 1}.16b
  eor v2.16b, v0.16b, v#{last}.16b
  st1 {v2.16b}, [x13], #16
  subs x11, x11, #1
  b.ne 1b
  eor v0.16b, v0.16b, v#{last}.16b
  st1 {v0.16b}, [x10]
" %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ chaining_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ block_count }})
        : "x9", "x10", "x11", "x12", "x13", "v0", "v1", "v2", "v8",
          "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30",
          "memory", "cc")
    end

    # CBC decryption of *group_count* groups of *blocks_per_group* blocks (8
    # or 1) with the round keys of the equivalent inverse cipher. The blocks
    # of a group are independent, so they run side by side. *chaining_block*
    # holds the initialization vector or the last ciphertext block, and is
    # left holding the last ciphertext block read.
    macro decrypt_chained_blocks(decryption_round_keys, chaining_block, input, output, group_count, round_count, blocks_per_group)
      {% key_count = round_count + 1 %}
      {% template = "  .arch_extension aes\n  mov x9, $0\n  mov x10, $1\n  mov x12, $2\n  mov x13, $3\n  mov x11, $4\n" %}
      {% for start in [0, 4, 8, 12] %}
        {% if start < key_count %}
          {% count = key_count - start %}
          {% if count > 4 %}{% count = 4 %}{% end %}
          {% registers = [] of StringLiteral %}
          {% for offset in 0...count %}{% registers << "v#{16 + start + offset}.16b" %}{% end %}
          {% template = template + "  ld1 {#{registers.join(", ").id}}, [x9], ##{count * 16}\n" %}
        {% end %}
      {% end %}
      {% template = template + "  ld1 {v31.16b}, [x10]\n1:\n" %}
      {% if blocks_per_group == 8 %}
        {% template = template + "  ld1 {v0.16b, v1.16b, v2.16b, v3.16b}, [x12], #64
  ld1 {v4.16b, v5.16b, v6.16b, v7.16b}, [x12], #64
  mov v8.16b, v0.16b
  mov v9.16b, v1.16b
  mov v10.16b, v2.16b
  mov v11.16b, v3.16b
  mov v12.16b, v4.16b
  mov v13.16b, v5.16b
  mov v14.16b, v6.16b
  mov v15.16b, v7.16b
" %}
      {% else %}
        {% template = template + "  ld1 {v0.16b}, [x12], #16\n  mov v8.16b, v0.16b\n" %}
      {% end %}
      {% for round in 0...(round_count - 1) %}
        {% for block in 0...blocks_per_group %}
          {% template = template + "  aesd v#{block}.16b, v#{16 + round}.16b\n  aesimc v#{block}.16b, v#{block}.16b\n" %}
        {% end %}
      {% end %}
      {% for block in 0...blocks_per_group %}
        {% previous = block == 0 ? "v31" : "v#{8 + block - 1}" %}
        {% template = template + "  aesd v#{block}.16b, v#{16 + round_count - 1}.16b
  eor v#{block}.16b, v#{block}.16b, v#{16 + round_count}.16b
  eor v#{block}.16b, v#{block}.16b, #{previous.id}.16b
" %}
      {% end %}
      {% if blocks_per_group == 8 %}
        {% template = template + "  st1 {v0.16b, v1.16b, v2.16b, v3.16b}, [x13], #64
  st1 {v4.16b, v5.16b, v6.16b, v7.16b}, [x13], #64
  mov v31.16b, v15.16b
" %}
      {% else %}
        {% template = template + "  st1 {v0.16b}, [x13], #16\n  mov v31.16b, v8.16b\n" %}
      {% end %}
      {% template = template + "  subs x11, x11, #1\n  b.ne 1b\n  st1 {v31.16b}, [x10]\n" %}
      asm({{ template }} :: "r"({{ decryption_round_keys }}), "r"({{ chaining_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }})
        : "x9", "x10", "x11", "x12", "x13",
          "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15",
          "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30", "v31",
          "memory", "cc")
    end

    # Blocks of ChaCha20 keystream one pass of `xor_chacha20_keystream`
    # produces: four side by side across the lanes of sixteen vector
    # registers, three more in four vector registers each, and one in
    # general registers.
    CHACHA20_BLOCKS_PER_GROUP = 9

    # CBC decryption of 2 * *pair_count* + 1 groups of eight blocks
    # (*pair_count* at least 1), software pipelined as the counter mode is:
    # two sets of eight registers take turns, one running the second half of
    # its rounds and being written out while the other starts the next
    # group. Each block is XORed with the ciphertext block stored just
    # before it, so the first block at *input* must not be the first of the
    # message: the caller decrypts the first group with
    # `decrypt_chained_blocks`.
    #
    # Registers: x9 round keys, x11 passes left, x12 input, x13 output; v0
    # to v15 the blocks, v16 to v30 the round keys, v31 a ciphertext block.
    macro decrypt_chained_blocks_pipelined(decryption_round_keys, input, output, pair_count, round_count)
      {% key_count = round_count + 1 %}
      {% template = "  .arch_extension aes\n  mov x9, $0\n  mov x12, $1\n  mov x13, $2\n  mov x11, $3\n" %}
      {% for start in [0, 4, 8, 12] %}
        {% if start < key_count %}
          {% count = key_count - start %}
          {% if count > 4 %}{% count = 4 %}{% end %}
          {% registers = [] of StringLiteral %}
          {% for offset in 0...count %}{% registers << "v#{16 + start + offset}.16b" %}{% end %}
          {% template = template + "  ld1 {#{registers.join(", ").id}}, [x9], ##{count * 16}\n" %}
        {% end %}
      {% end %}
      {% split = round_count // 2 %}
      {% list_of_load_lines = {} of NumberLiteral => StringLiteral %}
      {% list_of_early_rounds = {} of NumberLiteral => ArrayLiteral %}
      {% list_of_late_rounds = {} of NumberLiteral => ArrayLiteral %}
      {% for base in [0, 8] %}
        {% list_of_load_lines[base] = "  ld1 {v#{base}.16b, v#{base + 1}.16b, v#{base + 2}.16b, v#{base + 3}.16b}, [x12]\n  ldp q#{base + 4}, q#{base + 5}, [x12, #64]\n  ldp q#{base + 6}, q#{base + 7}, [x12, #96]\n" %}
        {% rounds = [] of ArrayLiteral %}
        {% for round in 0...split %}
          {% lines = [] of StringLiteral %}
          {% for block in 0...8 %}
            {% lines << "  aesd v#{base + block}.16b, v#{16 + round}.16b\n  aesimc v#{base + block}.16b, v#{base + block}.16b" %}
          {% end %}
          {% rounds << lines %}
        {% end %}
        {% list_of_early_rounds[base] = rounds %}
        {% rounds = [] of ArrayLiteral %}
        {% for round in split...(round_count - 1) %}
          {% lines = [] of StringLiteral %}
          {% for block in 0...8 %}
            {% lines << "  aesd v#{base + block}.16b, v#{16 + round}.16b\n  aesimc v#{base + block}.16b, v#{base + block}.16b" %}
          {% end %}
          {% rounds << lines %}
        {% end %}
        {% lines = [] of StringLiteral %}
        {% for block in 0...8 %}
          {% lines << "  aesd v#{base + block}.16b, v#{16 + round_count - 1}.16b\n  ldr q31, [x12, ##{block * 16 - 16}]\n  eor v#{base + block}.16b, v#{base + block}.16b, v#{16 + round_count}.16b\n  eor v#{base + block}.16b, v#{base + block}.16b, v31.16b" %}
        {% end %}
        {% lines << "  st1 {v#{base}.16b, v#{base + 1}.16b, v#{base + 2}.16b, v#{base + 3}.16b}, [x13], #64\n  st1 {v#{base + 4}.16b, v#{base + 5}.16b, v#{base + 6}.16b, v#{base + 7}.16b}, [x13], #64\n  add x12, x12, #128" %}
        {% rounds << lines %}
        {% list_of_late_rounds[base] = rounds %}
      {% end %}
      # The set that starts reads the group after the one finishing, at
      # x12 + 128 until the finishing set moves x12 on.
      {% template = template + list_of_load_lines[0] %}
      {% for lines in list_of_early_rounds[0] %}
        {% template = template + lines.join("\n") + "\n" %}
      {% end %}
      {% template = template + "1:\n" %}
      {% for roles in [[0, 8], [8, 0]] %}
        {% finishing = roles[0] %}
        {% starting = roles[1] %}
        {% template = template + "  ldp q#{starting}, q#{starting + 1}, [x12, #128]\n  ldp q#{starting + 2}, q#{starting + 3}, [x12, #160]\n  ldp q#{starting + 4}, q#{starting + 5}, [x12, #192]\n  ldp q#{starting + 6}, q#{starting + 7}, [x12, #224]\n" %}
        {% step_count = list_of_late_rounds[finishing].size %}
        {% if list_of_early_rounds[starting].size > step_count %}
          {% step_count = list_of_early_rounds[starting].size %}
        {% end %}
        {% for step in 0...step_count %}
          {% late_lines = list_of_late_rounds[finishing][step] %}
          {% early_lines = list_of_early_rounds[starting][step] %}
          {% for index in 0...9 %}
            {% if late_lines && late_lines[index] %}
              {% template = template + late_lines[index] + "\n" %}
            {% end %}
            {% if early_lines && early_lines[index] %}
              {% template = template + early_lines[index] + "\n" %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
      {% template = template + "  subs x11, x11, #1\n  b.ne 1b\n" %}
      {% for lines in list_of_late_rounds[0] %}
        {% template = template + lines.join("\n") + "\n" %}
      {% end %}
      asm({{ template }} :: "r"({{ decryption_round_keys }}), "r"({{ input }}), "r"({{ output }}), "r"({{ pair_count }})
        : "x9", "x11", "x12", "x13",
          "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15",
          "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30", "v31",
          "memory", "cc")
    end

    # ChaCha20 (RFC 8439 §2.3): XORs the keystream of the sixteen-word
    # state at *state* into *group_count* (at least 1) groups of eight
    # 64-byte blocks at *input* and writes them to *output*. Word 12 of the
    # state is the counter of the first block; it is left at the counter of
    # the block after the last one, wrapping at 2^32.
    #
    # Twenty rounds are a chain of additions, XORs and rotations in which
    # each step needs the one before, and a vector step takes two cycles, so
    # a processor that starts four vector instructions a cycle needs eight
    # chains at once to stay busy. Four blocks run side by side, one word of
    # each block in each lane of sixteen registers, which gives the four
    # quarter rounds of a round as four chains; three more blocks each keep
    # their four rows in four registers, a chain each, with `ext` turning
    # the columns into diagonals between the two halves of a double round.
    # The eighth block runs on the general registers, whose units the vector
    # code leaves idle. The rotations by 16 and 8 are byte moves (`rev32` and
    # `tbl`); those by 12 and 7 shift into a spare register, which then takes
    # the word's place, so no instruction is spent moving values back.
    #
    # Registers: x9 the state, x11 groups left, x12 input, x13 output, w16
    # the counter, w17 scratch, sixteen more general registers the eighth
    # block; v28 the byte order of a rotation by 8, v29 the lane numbers 0
    # to 3, the other vector registers the seven vector blocks and two
    # spares.
    macro xor_chacha20_keystream(state, input, output, group_count, absorbs_poly1305 = false, poly1305_input = nil)
      # Logical words: 0 to 15 are the words of the four side-by-side blocks,
      # 16 + 4 * block + row the rows of the three row-held blocks. *register*
      # maps each to the vector register holding it; *spares* holds the free
      # vector registers, taken and given back in turn.
      {% register = {} of NumberLiteral => NumberLiteral %}
      {% row_block_count = 3 %}
      {% table = 16 + row_block_count * 4 %}
      {% lanes = table + 1 %}
      {% for word in 0...table %}
        {% register[word] = word %}
      {% end %}
      {% scalar = ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7", "w8", "w10", "w14", "w15", "w19", "w20", "w21", "w22"] %}
      {% spares = {} of NumberLiteral => NumberLiteral %}
      {% for number in (lanes + 1)...32 %}
        {% spares[number - lanes - 1] = number %}
      {% end %}
      {% spare_count = 31 - lanes %}
      {% next_spare = 0 %}
      {% template = "  mov x9, $0\n  mov x12, $1\n  mov x13, $2\n  mov x11, $3\n  ldr w16, [x9, #48]\n" %}
      {% block_count = 6 + row_block_count %}
      {% side_lines = [] of StringLiteral %}
      {% if absorbs_poly1305 %}
        {% block_count = 4 + row_block_count %}
        # Poly1305 on the general registers: x0, x1, x2 the accumulator, x3
        # and x4 r, x5 r1 + r1 / 4, x6 the blocks to absorb, x22 the 1 of
        # bit 128, the rest products. One block: h += m + 2^128, then
        # h = h * r with the bits from 2^130 up folded back times 5.
        {% template = template + "  mov x6, $4\n  ldp x0, x1, [x9, #64]\n  ldr x2, [x9, #80]\n  ldp x3, x4, [x9, #88]\n  add x5, x4, x4, lsr #2\n  mov x22, #1\n" %}
        {% for block in 0...(block_count * 4) %}
          {% for line in ["ldp x7, x8, [x6], #16", "adds x0, x0, x7", "adcs x1, x1, x8", "adc x2, x2, x22",
                          "mul x7, x0, x3", "umulh x8, x0, x3", "mul x10, x1, x5", "umulh x14, x1, x5",
                          "mul x15, x0, x4", "umulh x19, x0, x4", "mul x20, x1, x3", "umulh x21, x1, x3",
                          "adds x7, x7, x10", "adc x8, x8, x14", "mul x10, x2, x5", "mul x14, x2, x3",
                          "adds x15, x15, x20", "adc x19, x19, x21", "adds x15, x15, x10", "adc x19, x19, xzr",
                          "adds x15, x15, x8", "adc x19, x19, xzr", "add x14, x14, x19",
                          "and x10, x14, #0xfffffffffffffffc", "add x10, x10, x14, lsr #2", "and x2, x14, #3",
                          "adds x0, x7, x10", "adcs x1, x15, xzr", "adc x2, x2, xzr"] %}
            {% side_lines << line %}
          {% end %}
        {% end %}
      {% end %}
      {% unless absorbs_poly1305 %}
        # Two blocks on the general registers, one after the other: the
        # first finishes and is written out while the vector rounds run.
        {% for general_block in 0...2 %}
          {% counter_offset = 4 + row_block_count + general_block %}
          {% for pair in 0...8 %}
            {% side_lines << "ldp #{scalar[pair * 2].id}, #{scalar[pair * 2 + 1].id}, [x9, ##{pair * 8}]" %}
          {% end %}
          {% side_lines << "add #{scalar[12].id}, w16, ##{counter_offset}" %}
          {% for double_round in 0...10 %}
            {% for columns in [[[0, 4, 8, 12], [1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15]], [[0, 5, 10, 15], [1, 6, 11, 12], [2, 7, 8, 13], [3, 4, 9, 14]]] %}
              {% for step in [[0, 1, 3, 16], [2, 3, 1, 12], [0, 1, 3, 8], [2, 3, 1, 7]] %}
                {% for words in columns %}
                  {% side_lines << "add #{scalar[words[step[0]]].id}, #{scalar[words[step[0]]].id}, #{scalar[words[step[1]]].id}" %}
                {% end %}
                {% for words in columns %}
                  {% side_lines << "eor #{scalar[words[step[2]]].id}, #{scalar[words[step[2]]].id}, #{scalar[words[step[0]]].id}" %}
                {% end %}
                {% for words in columns %}
                  {% side_lines << "ror #{scalar[words[step[2]]].id}, #{scalar[words[step[2]]].id}, ##{32 - step[3]}" %}
                {% end %}
              {% end %}
            {% end %}
          {% end %}
          {% for word in 0...16 %}
            {% if word == 12 %}
              {% side_lines << "add w17, w16, ##{counter_offset}" %}
            {% else %}
              {% side_lines << "ldr w17, [x9, ##{word * 4}]" %}
            {% end %}
            {% side_lines << "add #{scalar[word].id}, #{scalar[word].id}, w17" %}
            {% side_lines << "ldr w17, [x12, ##{counter_offset * 64 + word * 4}]" %}
            {% side_lines << "eor #{scalar[word].id}, #{scalar[word].id}, w17" %}
            {% side_lines << "str #{scalar[word].id}, [x13, ##{counter_offset * 64 + word * 4}]" %}
          {% end %}
        {% end %}
      {% end %}
      {% side_per_step = (side_lines.size + 79) // 80 %}
      {% side_next = 0 %}
      {% template = template + "1:\n" %}
      # v#{table}: within each 32-bit lane, the bytes in the order 3, 0, 1, 2.
      {% template = template + "  movz x17, #0x0003\n  movk x17, #0x0201, lsl #16\n  movk x17, #0x0407, lsl #32\n  movk x17, #0x0605, lsl #48\n  mov v#{table}.d[0], x17\n" %}
      {% template = template + "  movz x17, #0x080b\n  movk x17, #0x0a09, lsl #16\n  movk x17, #0x0c0f, lsl #32\n  movk x17, #0x0e0d, lsl #48\n  mov v#{table}.d[1], x17\n" %}
      {% template = template + "  movi v#{lanes}.4s, #0\n  mov w17, #1\n  mov v#{lanes}.s[1], w17\n  mov w17, #2\n  mov v#{lanes}.s[2], w17\n  mov w17, #3\n  mov v#{lanes}.s[3], w17\n" %}

      # The state of this group: the side-by-side blocks take each word in
      # every lane, with counters +0 to +3; the row-held ones take the state as
      # rows, with counters +4 to +6, and the general-register block +7.
      {% for quarter in 0...4 %}
        {% template = template + "  ld4r {v#{quarter * 4}.4s, v#{quarter * 4 + 1}.4s, v#{quarter * 4 + 2}.4s, v#{quarter * 4 + 3}.4s}, [x9], #16\n" %}
      {% end %}
      {% template = template + "  sub x9, x9, #64\n  dup v12.4s, w16\n  add v12.4s, v12.4s, v#{lanes}.4s\n" %}
      {% for block in 0...row_block_count %}
        {% template = template + "  ld1 {v#{16 + block * 4}.4s, v#{17 + block * 4}.4s, v#{18 + block * 4}.4s, v#{19 + block * 4}.4s}, [x9]\n  add w17, w16, ##{4 + block}\n  mov v#{19 + block * 4}.s[0], w17\n" %}
      {% end %}


      {% for double_round in 0...10 %}
        {% for half in 0...2 %}
          {% if half == 0 %}
            {% columns = [[0, 4, 8, 12], [1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15]] %}
          {% else %}
            {% columns = [[0, 5, 10, 15], [1, 6, 11, 12], [2, 7, 8, 13], [3, 4, 9, 14]] %}
          {% end %}
          {% quarter_rounds = columns.map { |words| words } %}
          {% for block in 0...row_block_count %}
            {% quarter_rounds << [16 + block * 4, 17 + block * 4, 18 + block * 4, 19 + block * 4] %}
          {% end %}
          # Each step of the quarter round, for all seven vector chains and the general-register block:
          # {a, b, d, rotation} means a += b, d ^= a, d <<<= rotation.
          {% for step in [[0, 1, 3, 16], [2, 3, 1, 12], [0, 1, 3, 8], [2, 3, 1, 7]] %}
            {% for words in quarter_rounds %}
              {% target = register[words[step[0]]] %}
              {% template = template + "  add v#{target}.4s, v#{target}.4s, v#{register[words[step[1]]]}.4s\n" %}
            {% end %}

            {% for words in quarter_rounds %}
              {% target = register[words[step[2]]] %}
              {% template = template + "  eor v#{target}.16b, v#{target}.16b, v#{register[words[step[0]]]}.16b\n" %}
            {% end %}

            {% for words in quarter_rounds %}
              {% word = words[step[2]] %}
              {% if step[3] == 16 %}
                {% template = template + "  rev32 v#{register[word]}.8h, v#{register[word]}.8h\n" %}
              {% elsif step[3] == 8 %}
                {% template = template + "  tbl v#{register[word]}.16b, {v#{register[word]}.16b}, v#{table}.16b\n" %}
              {% else %}
                {% spare = spares[next_spare] %}
                {% template = template + "  ushr v#{spare}.4s, v#{register[word]}.4s, ##{32 - step[3]}\n  sli v#{spare}.4s, v#{register[word]}.4s, ##{step[3]}\n" %}
                {% spares[next_spare] = register[word] %}
                {% register[word] = spare %}
                {% next_spare = (next_spare + 1) % spare_count %}
              {% end %}
            {% end %}
            {% for index in 0...side_per_step %}
              {% if side_next < side_lines.size %}
                {% template = template + "  " + side_lines[side_next] + "\n" %}
                {% side_next = side_next + 1 %}
              {% end %}
            {% end %}
          {% end %}
          # The row-held blocks turn columns into diagonals and back.
          {% for block in 0...row_block_count %}
            {% for row in 1...4 %}
              {% shift = half == 0 ? row * 4 : 16 - row * 4 %}
              {% name = register[16 + block * 4 + row] %}
              {% template = template + "  ext v#{name}.16b, v#{name}.16b, v#{name}.16b, ##{shift}\n" %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}

      # The side-by-side blocks: add the state back, four words at a time,
      # turn each four words of four blocks into four words of one block,
      # then XOR the input and store, a block at a time.
      {% first_spare = spares[next_spare] %}
      {% template = template + "  dup v#{first_spare}.4s, w16\n  add v#{first_spare}.4s, v#{first_spare}.4s, v#{lanes}.4s\n  add v#{register[12]}.4s, v#{register[12]}.4s, v#{first_spare}.4s\n" %}
      {% loaded = [] of NumberLiteral %}
      {% for offset in 0...spare_count %}
        {% loaded << spares[(next_spare + offset) % spare_count] %}
      {% end %}
      {% loaded << table %}
      {% loaded << lanes %}
      {% for quarter in 0...4 %}
        {% for offset in 0...4 %}
          {% template = template + "  ld1r {v#{loaded[offset]}.4s}, [x9], #4\n" %}
        {% end %}
        {% for offset in 0...4 %}
          {% if quarter != 3 || offset != 0 %}
            {% name = register[quarter * 4 + offset] %}
            {% template = template + "  add v#{name}.4s, v#{name}.4s, v#{loaded[offset]}.4s\n" %}
          {% end %}
        {% end %}
        # Words w0..w3 (lane = block) to rows: trn on 32-bit lanes, then on
        # 64-bit lanes. The four loaded registers are free again and take
        # the first results.
        {% w = [register[quarter * 4], register[quarter * 4 + 1], register[quarter * 4 + 2], register[quarter * 4 + 3]] %}
        {% t = loaded %}
        {% template = template + "  trn1 v#{t[0]}.4s, v#{w[0]}.4s, v#{w[1]}.4s\n  trn2 v#{t[1]}.4s, v#{w[0]}.4s, v#{w[1]}.4s\n  trn1 v#{t[2]}.4s, v#{w[2]}.4s, v#{w[3]}.4s\n  trn2 v#{t[3]}.4s, v#{w[2]}.4s, v#{w[3]}.4s\n" %}
        {% template = template + "  trn1 v#{w[0]}.2d, v#{t[0]}.2d, v#{t[2]}.2d\n  trn1 v#{w[1]}.2d, v#{t[1]}.2d, v#{t[3]}.2d\n  trn2 v#{w[2]}.2d, v#{t[0]}.2d, v#{t[2]}.2d\n  trn2 v#{w[3]}.2d, v#{t[1]}.2d, v#{t[3]}.2d\n" %}
        # Now register[quarter * 4 + block] holds words 4*quarter.. of *block*.
      {% end %}
      {% template = template + "  sub x9, x9, #64\n" %}
      {% for block in 0...4 %}
        {% template = template + "  ldp q#{loaded[0]}, q#{loaded[1]}, [x12, ##{block * 64}]\n  ldp q#{loaded[2]}, q#{loaded[3]}, [x12, ##{block * 64 + 32}]\n" %}
        {% for quarter in 0...4 %}
          {% name = register[quarter * 4 + block] %}
          {% template = template + "  eor v#{name}.16b, v#{name}.16b, v#{loaded[quarter]}.16b\n" %}
        {% end %}
        {% template = template + "  stp q#{register[block]}, q#{register[4 + block]}, [x13, ##{block * 64}]\n  stp q#{register[8 + block]}, q#{register[12 + block]}, [x13, ##{block * 64 + 32}]\n" %}
      {% end %}

      # The row-held blocks: add the state back, XOR the input, store.
      {% for block in 0...row_block_count %}
        {% template = template + "  ldp q#{loaded[0]}, q#{loaded[1]}, [x9]\n  ldp q#{loaded[2]}, q#{loaded[3]}, [x9, #32]\n  add w17, w16, ##{4 + block}\n  mov v#{loaded[3]}.s[0], w17\n" %}
        {% for row in 0...4 %}
          {% name = register[16 + block * 4 + row] %}
          {% template = template + "  add v#{name}.4s, v#{name}.4s, v#{loaded[row]}.4s\n" %}
        {% end %}
        {% template = template + "  ldp q#{loaded[0]}, q#{loaded[1]}, [x12, ##{256 + block * 64}]\n  ldp q#{loaded[2]}, q#{loaded[3]}, [x12, ##{256 + block * 64 + 32}]\n" %}
        {% for row in 0...4 %}
          {% name = register[16 + block * 4 + row] %}
          {% template = template + "  eor v#{name}.16b, v#{name}.16b, v#{loaded[row]}.16b\n" %}
        {% end %}
        {% template = template + "  stp q#{register[16 + block * 4]}, q#{register[17 + block * 4]}, [x13, ##{256 + block * 64}]\n  stp q#{register[18 + block * 4]}, q#{register[19 + block * 4]}, [x13, ##{256 + block * 64 + 32}]\n" %}
      {% end %}
      {% while_poly1305_left = side_lines.size - side_next %}
      {% for index in 0...while_poly1305_left %}
        {% template = template + "  " + side_lines[side_next + index] + "\n" %}
      {% end %}
      {% template = template + "  add x12, x12, ##{block_count * 64}\n  add x13, x13, ##{block_count * 64}\n  add w16, w16, ##{block_count}\n  subs x11, x11, #1\n  b.ne 1b\n  str w16, [x9, #48]\n" %}
      {% if absorbs_poly1305 %}
        {% template = template + "  stp x0, x1, [x9, #64]\n  str x2, [x9, #80]\n" %}
      {% end %}
      asm({{ template }} :: "r"({{ state }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }}), "r"({{ poly1305_input || 0_u64 }})
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17",
          "x19", "x20", "x21", "x22",
          "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15",
          "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30", "v31",
          "memory", "cc")
    end

    # ChaCha20 on the general registers, for messages too short to fill a
    # vector group: *block_count* (at least 1) blocks one after the other,
    # their keystream XORed into *input* and written to *output*, word 12 of
    # the state at *state* left at the next counter. With
    # *writes_subkey*, one HChaCha20 block instead (draft-irtf-cfrg-xchacha-03
    # §2.2): the 32 bytes of words 0 to 3 and 12 to 15 after the rounds,
    # without the state added back, are written to *output*, and *input* is
    # not read.
    #
    # A block's quarter rounds are four chains of one-cycle steps, so one
    # block takes about 240 cycles, where a vector group takes about 600.
    #
    # Registers: x9 the state, x11 blocks left, x12 input, x13 output, w17
    # scratch, sixteen more general registers the block.
    macro xor_chacha20_keystream_on_general_registers(state, input, output, block_count, writes_subkey = false,
                                                      derives_subkey_first = false)
      {% words = ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7", "w8", "w10", "w14", "w15", "w19", "w20", "w21", "w22"] %}
      {% rounds = [] of StringLiteral %}
      {% for pair in 0...8 %}
        {% rounds << "  ldp #{words[pair * 2].id}, #{words[pair * 2 + 1].id}, [x9, ##{pair * 8}]\n" %}
      {% end %}
      {% for double_round in 0...10 %}
        {% for columns in [[[0, 4, 8, 12], [1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15]], [[0, 5, 10, 15], [1, 6, 11, 12], [2, 7, 8, 13], [3, 4, 9, 14]]] %}
          {% for step in [[0, 1, 3, 16], [2, 3, 1, 12], [0, 1, 3, 8], [2, 3, 1, 7]] %}
            {% for quarter in columns %}
              {% rounds << "  add #{words[quarter[step[0]]].id}, #{words[quarter[step[0]]].id}, #{words[quarter[step[1]]].id}\n" %}
            {% end %}
            {% for quarter in columns %}
              {% rounds << "  eor #{words[quarter[step[2]]].id}, #{words[quarter[step[2]]].id}, #{words[quarter[step[0]]].id}\n" %}
            {% end %}
            {% for quarter in columns %}
              {% rounds << "  ror #{words[quarter[step[2]]].id}, #{words[quarter[step[2]]].id}, ##{32 - step[3]}\n" %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
      {% template = "  mov x9, $0\n  mov x12, $1\n  mov x13, $2\n  mov x11, $3\n" %}
      {% if derives_subkey_first %}
        # HChaCha20 on the state, whose words 16 and 17 hold the last eight
        # nonce bytes; its output becomes the key of the state the blocks
        # then run on, with counter 0 and nonce 0, word 16, word 17.
        {% template = template + rounds.join("") %}
        {% template = template + "  stp #{words[0].id}, #{words[1].id}, [x9, #16]\n  stp #{words[2].id}, #{words[3].id}, [x9, #24]\n" %}
        {% template = template + "  stp #{words[12].id}, #{words[13].id}, [x9, #32]\n  stp #{words[14].id}, #{words[15].id}, [x9, #40]\n" %}
        {% template = template + "  ldp w17, #{words[0].id}, [x9, #64]\n  stp wzr, wzr, [x9, #48]\n  stp w17, #{words[0].id}, [x9, #56]\n" %}
      {% end %}
      {% template = template + "1:\n" %}
      {% template = template + rounds.join("") %}
      {% if writes_subkey %}
        {% for index in 0...4 %}
          {% template = template + "  str #{words[index].id}, [x13, ##{index * 4}]\n  str #{words[12 + index].id}, [x13, ##{16 + index * 4}]\n" %}
        {% end %}
      {% else %}
        {% for word in 0...16 %}
          {% template = template + "  ldr w17, [x9, ##{word * 4}]\n  add #{words[word].id}, #{words[word].id}, w17\n  ldr w17, [x12, ##{word * 4}]\n  eor #{words[word].id}, #{words[word].id}, w17\n  str #{words[word].id}, [x13, ##{word * 4}]\n" %}
        {% end %}
        {% template = template + "  ldr w17, [x9, #48]\n  add w17, w17, #1\n  str w17, [x9, #48]\n  add x12, x12, #64\n  add x13, x13, #64\n" %}
      {% end %}
      {% template = template + "  subs x11, x11, #1\n  b.ne 1b\n" %}
      asm({{ template }} :: "r"({{ state }}), "r"({{ input }}), "r"({{ output }}), "r"({{ block_count }})
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x17",
          "x19", "x20", "x21", "x22", "memory", "cc")
    end
  end
end
