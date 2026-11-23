module Amber::Beryl::Crypto
  # :nodoc:
  #
  # AES and GHASH written with the instructions of x86-64 processors
  # (Intel 64 and IA-32 Architectures Software Developer's Manual, volume 2):
  # AES-NI (`aesenc`, `aesenclast`, `aesdec`, `aesdeclast`, `aesimc`) for
  # AES and `pclmulqdq` (carry-less multiplication) for GHASH, with the
  # SSSE3 `pshufb` and the SSE4.1 `pinsrd`. Each macro has the parameters,
  # memory layouts and meaning of its twin in `Armv8CipherInstructions`, so
  # the callers in `V1::GaloisCounterModeWithProcessorInstructions` and the
  # CBC mode use either one the same way.
  #
  # Crystal has no vector types, so the instructions cannot be reached as
  # LLVM intrinsics; the assembly is written out here instead, as in
  # `X8664HashInstructions`. Every statement has at most one branch, which
  # closes its loop on the count of groups left, and reads and writes memory
  # only at fixed offsets from its inputs, so its timing depends on the sizes
  # it is given and on nothing a key or a message holds.
  # `scripts/check_secret_flow.rb` checks exactly that. The AES and
  # carry-less multiply instructions take the same time whatever their
  # operands hold.
  #
  # Every vector instruction takes its operands from registers: the legacy
  # SSE forms of these instructions fault on a memory operand that is not
  # 16-byte aligned, and the buffers they are given may not be, so memory is
  # reached only through `movdqu`.
  #
  # GHASH works on blocks with their sixteen bytes reversed (`pshufb` with
  # the mask stored after each statement), so that the field's bit order
  # matches the processor's, and on hash key powers multiplied by x once
  # ("twisted") when they were prepared. A product is three carry-less
  # multiplies (Karatsuba), and the reduction modulo
  # x^128 + x^7 + x^2 + x + 1 is shifts and exclusive ors. This is the
  # method of Gueron and Kounavis, "Intel Carry-Less Multiplication
  # Instruction and its Usage for Computing the GCM Mode" (2014), in the
  # arrangement OpenSSL's `ghash-x86_64` uses; the vectors and the
  # differential against libcrypto check it. The accumulator in memory is
  # the GHASH state with its bytes reversed, as on AArch64.
  module X8664CipherInstructions
    # Bytes in one table entry of hash key powers: the twisted power, then
    # the exclusive or of its two 64-bit halves in both halves (the middle
    # operand of the Karatsuba multiply).
    HASH_KEY_POWER_BYTESIZE = 32

    # Powers of the hash key kept: H to H^16, one per block of a group.
    HASH_KEY_POWER_COUNT = 16

    # The constants each statement reads after its code: the mask that
    # reverses sixteen bytes, then the twisting polynomial (1 in the lowest
    # byte, 0xc2 in the highest).
    CONSTANT_LINES = "  jmp 9f\n  .p2align 4\n8:\n  .quad 0x08090a0b0c0d0e0f\n  .quad 0x0001020304050607\n  .quad 0x0000000000000001\n  .quad 0xc200000000000000\n9:\n"

    # Reduces the 256-bit product with its low half in register `@L` and its
    # high half in `@H` to 128 bits in `@L` (OpenSSL's `reduction_alg9`),
    # with `@A` and `@B` as scratch. The macros replace the four names with
    # registers.
    REDUCTION_LINES = "  movdqa @L, @B
  movdqa @L, @A
  psllq $$5, @L
  pxor @L, @A
  psllq $$1, @L
  pxor @A, @L
  psllq $$57, @L
  movdqa @L, @A
  pslldq $$8, @L
  psrldq $$8, @A
  pxor @B, @L
  pxor @A, @H
  movdqa @L, @B
  psrlq $$1, @L
  pxor @B, @H
  pxor @L, @B
  psrlq $$5, @L
  pxor @B, @L
  psrlq $$1, @L
  pxor @H, @L
"

    # Prepares the table of hash key powers at *hash_key_powers*
    # (`HASH_KEY_POWER_COUNT` entries of `HASH_KEY_POWER_BYTESIZE` bytes) from
    # the hash key at *hash_key* (16 bytes, the encryption of the zero
    # block). The highest power comes first: entry j holds H^(16 - j), so
    # that n blocks hashed together take the n entries from 16 - n on. No
    # loop: fifteen multiplies written out.
    #
    # Registers: r8 hash key, r9 table, rax constants; xmm3 twisted H, xmm4
    # its Karatsuba operand, xmm0 the running power.
    macro prepare_hash_key_powers(hash_key, hash_key_powers)
      {% template = "
  mov $0, %r8
  mov $1, %r9
  lea 8f(%rip), %rax
  movdqu (%r8), %xmm3
  movdqu (%rax), %xmm7
  pshufb %xmm7, %xmm3
  pshufd $$0xff, %xmm3, %xmm2
  movdqa %xmm3, %xmm1
  psllq $$1, %xmm3
  pxor %xmm5, %xmm5
  psrlq $$63, %xmm1
  pcmpgtd %xmm2, %xmm5
  pslldq $$8, %xmm1
  por %xmm1, %xmm3
  movdqu 16(%rax), %xmm6
  pand %xmm6, %xmm5
  pxor %xmm5, %xmm3
  pshufd $$0x4e, %xmm3, %xmm4
  pxor %xmm3, %xmm4
  movdqu %xmm3, 480(%r9)
  movdqu %xmm4, 496(%r9)
  movdqa %xmm3, %xmm0
" %}
      {% for power in 2..16 %}
        {% template = template + "  movdqa %xmm0, %xmm1
  pshufd $$0x4e, %xmm0, %xmm2
  pxor %xmm0, %xmm2
  pclmulqdq $$0x00, %xmm3, %xmm0
  pclmulqdq $$0x11, %xmm3, %xmm1
  pclmulqdq $$0x00, %xmm4, %xmm2
  pxor %xmm0, %xmm2
  pxor %xmm1, %xmm2
  movdqa %xmm2, %xmm5
  psrldq $$8, %xmm2
  pslldq $$8, %xmm5
  pxor %xmm2, %xmm1
  pxor %xmm5, %xmm0
" + ::Beryl::Crypto::X8664CipherInstructions::REDUCTION_LINES.gsub(/@L/, "%xmm0").gsub(/@H/, "%xmm1").gsub(/@A/, "%xmm5").gsub(/@B/, "%xmm6") + "  pshufd $$0x4e, %xmm0, %xmm2
  pxor %xmm0, %xmm2
  movdqu %xmm0, #{(16 - power) * 32}(%r9)
  movdqu %xmm2, #{(16 - power) * 32 + 16}(%r9)
" %}
      {% end %}
      {% template = template + ::Beryl::Crypto::X8664CipherInstructions::CONSTANT_LINES %}
      asm({{ template }} :: "r"({{ hash_key }}), "r"({{ hash_key_powers }})
        : "rax", "r8", "r9", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "memory", "cc")
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
    #   block only: xmm10 holds it for the first pass and zero after.
    #
    # Each block is byte-reversed and multiplied by its power as three
    # carry-less multiplies; the low (xmm11), high (xmm12) and middle
    # (xmm13) products are summed and reduced once. In a group of sixteen,
    # block 0 is hashed last, since it alone waits for the accumulator.
    #
    # Registers: r8 the accumulator, r9 hash key powers, r10 input, r11
    # groups left, rax constants; xmm14 the accumulator, xmm15 the
    # byte-reversing mask, xmm0 to xmm9 two sets of block, power and product
    # registers that alternate.
    macro absorb_hash_blocks(accumulator, first_hash_key_power, input, group_count, blocks_per_group)
      {% template = "  mov $0, %r8\n  mov $1, %r9\n  mov $2, %r10\n  mov $3, %r11\n  lea 8f(%rip), %rax\n  movdqu (%rax), %xmm15\n  movdqu (%r8), %xmm14\n" %}
      {% reduction = ::Beryl::Crypto::X8664CipherInstructions::REDUCTION_LINES.gsub(/@L/, "%xmm11").gsub(/@H/, "%xmm12").gsub(/@A/, "%xmm1").gsub(/@B/, "%xmm2") %}
      {% if blocks_per_group == 16 %}
        {% template = template + "1:\n" %}
        {% for block in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0] %}
          {% base = (block % 2) * 5 %}
          {% x = "%xmm#{base}" %}
          {% high = "%xmm#{base + 1}" %}
          {% middle = "%xmm#{base + 2}" %}
          {% power = "%xmm#{base + 3}" %}
          {% karatsuba = "%xmm#{base + 4}" %}
          {% template = template + "  movdqu #{block * 16}(%r10), #{x.id}\n  pshufb %xmm15, #{x.id}\n" %}
          {% if block == 0 %}
            {% template = template + "  pxor %xmm14, #{x.id}\n" %}
          {% end %}
          {% template = template + "  movdqu #{block * 32}(%r9), #{power.id}
  movdqu #{block * 32 + 16}(%r9), #{karatsuba.id}
  pshufd $$0x4e, #{x.id}, #{middle.id}
  pxor #{x.id}, #{middle.id}
  movdqa #{x.id}, #{high.id}
  pclmulqdq $$0x00, #{power.id}, #{x.id}
  pclmulqdq $$0x11, #{power.id}, #{high.id}
  pclmulqdq $$0x00, #{karatsuba.id}, #{middle.id}
" %}
          {% if block == 1 %}
            {% template = template + "  movdqa #{x.id}, %xmm11\n  movdqa #{high.id}, %xmm12\n  movdqa #{middle.id}, %xmm13\n" %}
          {% else %}
            {% template = template + "  pxor #{x.id}, %xmm11\n  pxor #{high.id}, %xmm12\n  pxor #{middle.id}, %xmm13\n" %}
          {% end %}
        {% end %}
      {% else %}
        {% template = template + "  pxor %xmm11, %xmm11\n  pxor %xmm12, %xmm12\n  pxor %xmm13, %xmm13\n  movdqa %xmm14, %xmm10\n1:
  movdqu (%r10), %xmm0
  pshufb %xmm15, %xmm0
  pxor %xmm10, %xmm0
  pxor %xmm10, %xmm10
  movdqu (%r9), %xmm3
  movdqu 16(%r9), %xmm4
  pshufd $$0x4e, %xmm0, %xmm2
  pxor %xmm0, %xmm2
  movdqa %xmm0, %xmm1
  pclmulqdq $$0x00, %xmm3, %xmm0
  pclmulqdq $$0x11, %xmm3, %xmm1
  pclmulqdq $$0x00, %xmm4, %xmm2
  pxor %xmm0, %xmm11
  pxor %xmm1, %xmm12
  pxor %xmm2, %xmm13
  add $$16, %r10
  add $$32, %r9
  dec %r11
  jnz 1b
" %}
      {% end %}
      {% template = template + "  pxor %xmm11, %xmm13
  pxor %xmm12, %xmm13
  movdqa %xmm13, %xmm1
  psrldq $$8, %xmm13
  pslldq $$8, %xmm1
  pxor %xmm1, %xmm11
  pxor %xmm13, %xmm12
" + reduction + "  movdqa %xmm11, %xmm14\n" %}
      {% if blocks_per_group == 16 %}
        {% template = template + "  add $$256, %r10\n  dec %r11\n  jnz 1b\n" %}
      {% end %}
      {% template = template + "  movdqu %xmm14, (%r8)\n" + ::Beryl::Crypto::X8664CipherInstructions::CONSTANT_LINES %}
      asm({{ template }} :: "r"({{ accumulator }}), "r"({{ first_hash_key_power }}), "r"({{ input }}), "r"({{ group_count }})
        : "rax", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "cc")
    end

    # Counter mode: XORs the AES keystream of the counter block at
    # *counter_block* into whole blocks at *input* and writes them to
    # *output*. The last four bytes of the counter block count up as a
    # big-endian number that wraps at 2^32, and the counter block left behind
    # is the next one. *round_count* (10, 12 or 14) names how many of the
    # round keys at *round_keys* are used.
    #
    # - *is_pipelined* false: *group_count* (at least 1) single blocks, one
    #   per pass.
    # - *is_pipelined* true: 2 * *group_count* + 1 groups of eight blocks
    #   (*group_count* at least 1): two groups per pass and one after the
    #   loop. The eight blocks of a group go through each round side by side,
    #   so the processor always has independent AES instructions to start.
    #
    # Registers: r8 round keys, r9 counter block, r10 input, r11 output, rcx
    # passes left, edx the counter, eax a counter word; xmm0 to xmm7 the
    # blocks, xmm8 a round key, xmm9 a message block, xmm10 the last round
    # key, xmm11 the stored counter block, xmm12 the first round key. A
    # counter block is the stored block with its last word replaced; the
    # message is XORed into the last round key, which `aesenclast` adds at
    # its end.
    macro encrypt_counter_blocks(round_keys, counter_block, input, output, group_count, round_count, is_pipelined)
      {% template = "  mov $0, %r8\n  mov $1, %r9\n  mov $2, %r10\n  mov $3, %r11\n  mov $4, %rcx
  movdqu (%r9), %xmm11
  mov 12(%r9), %edx
  bswap %edx
  movdqu (%r8), %xmm12
  movdqu #{round_count * 16}(%r8), %xmm10
" %}
      {% block_count = is_pipelined ? 8 : 1 %}
      {% group_lines = "" %}
      {% for block in 0...block_count %}
        {% group_lines = group_lines + "  movdqa %xmm11, %xmm#{block}\n  lea #{block}(%rdx), %eax\n  bswap %eax\n  pinsrd $$3, %eax, %xmm#{block}\n  pxor %xmm12, %xmm#{block}\n" %}
      {% end %}
      {% group_lines = group_lines + "  add $$#{block_count}, %edx\n" %}
      {% for round in 1...round_count %}
        {% group_lines = group_lines + "  movdqu #{round * 16}(%r8), %xmm8\n" %}
        {% for block in 0...block_count %}
          {% group_lines = group_lines + "  aesenc %xmm8, %xmm#{block}\n" %}
        {% end %}
      {% end %}
      {% for block in 0...block_count %}
        {% group_lines = group_lines + "  movdqu #{block * 16}(%r10), %xmm9\n  pxor %xmm10, %xmm9\n  aesenclast %xmm9, %xmm#{block}\n  movdqu %xmm#{block}, #{block * 16}(%r11)\n" %}
      {% end %}
      {% group_lines = group_lines + "  add $$#{block_count * 16}, %r10\n  add $$#{block_count * 16}, %r11\n" %}
      {% if is_pipelined %}
        {% template = template + "1:\n" + group_lines + group_lines + "  dec %rcx\n  jnz 1b\n" + group_lines %}
      {% else %}
        {% template = template + "1:\n" + group_lines + "  dec %rcx\n  jnz 1b\n" %}
      {% end %}
      {% template = template + "  bswap %edx\n  mov %edx, 12(%r9)\n" %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ counter_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }})
        : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "memory", "cc")
    end

    # Writes at *decryption_round_keys* the round keys of the equivalent
    # inverse cipher (FIPS 197 §5.3.5) for the *round_count* rounds of the
    # encryption round keys at *round_keys*: the last key first, the middle
    # keys through `aesimc`, the first key last. No loop.
    macro prepare_decryption_round_keys(round_keys, decryption_round_keys, round_count)
      {% template = "  mov $0, %r8\n  mov $1, %r9\n" %}
      {% for index in 0..round_count %}
        {% template = template + "  movdqu #{(round_count - index) * 16}(%r8), %xmm0\n" %}
        {% if index > 0 && index < round_count %}
          {% template = template + "  aesimc %xmm0, %xmm0\n" %}
        {% end %}
        {% template = template + "  movdqu %xmm0, #{index * 16}(%r9)\n" %}
      {% end %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ decryption_round_keys }}) : "r8", "r9", "xmm0", "memory")
    end

    # CBC encryption (SP 800-38A §6.2) of *block_count* blocks (at least 1),
    # one after the other, since each depends on the last. *chaining_block*
    # holds the initialization vector or the last ciphertext block, and is
    # left holding the last ciphertext block written.
    #
    # Registers: r8 round keys, r9 chaining block, r10 input, r11 output, rcx
    # blocks left; xmm0 the chain, xmm1 the message block and then the first
    # round key, xmm2 to xmm15 the other round keys, kept in registers since
    # every block needs them all.
    macro encrypt_chained_blocks(round_keys, chaining_block, input, output, block_count, round_count)
      {% template = "  mov $0, %r8\n  mov $1, %r9\n  mov $2, %r10\n  mov $3, %r11\n  mov $4, %rcx\n  movdqu (%r9), %xmm0\n" %}
      {% for round in 1..round_count %}
        {% template = template + "  movdqu #{round * 16}(%r8), %xmm#{round + 1}\n" %}
      {% end %}
      {% template = template + "1:\n  movdqu (%r10), %xmm1\n  pxor %xmm1, %xmm0\n  movdqu (%r8), %xmm1\n  pxor %xmm1, %xmm0\n" %}
      {% for round in 1...round_count %}
        {% template = template + "  aesenc %xmm#{round + 1}, %xmm0\n" %}
      {% end %}
      {% template = template + "  aesenclast %xmm#{round_count + 1}, %xmm0
  movdqu %xmm0, (%r11)
  add $$16, %r10
  add $$16, %r11
  dec %rcx
  jnz 1b
  movdqu %xmm0, (%r9)
" %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ chaining_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ block_count }})
        : "rcx", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "cc")
    end

    # CBC decryption of *group_count* groups of *blocks_per_group* blocks (8
    # or 1) with the round keys of the equivalent inverse cipher. The blocks
    # of a group are independent, so they run side by side. *chaining_block*
    # holds the initialization vector or the last ciphertext block, and is
    # left holding the last ciphertext block read. Every ciphertext block a
    # group needs is read before its plaintext is written, so *output* may be
    # *input*.
    #
    # Registers: r8 round keys, r9 chaining block, r10 input, r11 output, rcx
    # groups left; xmm0 to xmm7 the blocks, xmm8 a round key, xmm9 a
    # ciphertext block, xmm10 the chain.
    macro decrypt_chained_blocks(decryption_round_keys, chaining_block, input, output, group_count, round_count, blocks_per_group)
      {% template = "  mov $0, %r8\n  mov $1, %r9\n  mov $2, %r10\n  mov $3, %r11\n  mov $4, %rcx\n  movdqu (%r9), %xmm10\n1:\n  movdqu (%r8), %xmm8\n" %}
      {% for block in 0...blocks_per_group %}
        {% template = template + "  movdqu #{block * 16}(%r10), %xmm#{block}\n  pxor %xmm8, %xmm#{block}\n" %}
      {% end %}
      {% for round in 1...round_count %}
        {% template = template + "  movdqu #{round * 16}(%r8), %xmm8\n" %}
        {% for block in 0...blocks_per_group %}
          {% template = template + "  aesdec %xmm8, %xmm#{block}\n" %}
        {% end %}
      {% end %}
      {% template = template + "  movdqu #{round_count * 16}(%r8), %xmm8\n" %}
      {% for block in 0...blocks_per_group %}
        {% template = template + "  aesdeclast %xmm8, %xmm#{block}\n" %}
        {% if block == 0 %}
          {% template = template + "  pxor %xmm10, %xmm0\n" %}
        {% else %}
          {% template = template + "  movdqu #{(block - 1) * 16}(%r10), %xmm9\n  pxor %xmm9, %xmm#{block}\n" %}
        {% end %}
      {% end %}
      {% template = template + "  movdqu #{(blocks_per_group - 1) * 16}(%r10), %xmm10\n" %}
      {% for block in 0...blocks_per_group %}
        {% template = template + "  movdqu %xmm#{block}, #{block * 16}(%r11)\n" %}
      {% end %}
      {% template = template + "  add $$#{blocks_per_group * 16}, %r10\n  add $$#{blocks_per_group * 16}, %r11\n  dec %rcx\n  jnz 1b\n  movdqu %xmm10, (%r9)\n" %}
      asm({{ template }} :: "r"({{ decryption_round_keys }}), "r"({{ chaining_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }})
        : "rcx", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "memory", "cc")
    end

    # Blocks of ChaCha20 keystream one pass of `xor_chacha20_keystream`
    # produces: three blocks, each held as its four rows in four registers,
    # which with two scratch registers and the two byte-order masks fill the
    # sixteen that SSE has.
    CHACHA20_BLOCKS_PER_GROUP = 3

    # ChaCha20 (RFC 8439 §2.3): XORs the keystream of the sixteen-word
    # state at *state* into *group_count* (at least 1) groups of
    # `CHACHA20_BLOCKS_PER_GROUP` 64-byte blocks at *input* and writes them
    # to *output*, which may be *input*. Word 12 of the state is the counter
    # of the first block; it is left at the counter of the block after the
    # last one, wrapping at 2^32.
    #
    # Each block keeps its rows in four registers, so a quarter round works
    # on all four columns at once; `pshufd` turns the columns into diagonals
    # between the two halves of a double round and back. The three blocks
    # are interleaved step by step, three independent chains. The rotations
    # by 16 and 8 are byte moves (`pshufb` with the masks stored after the
    # code); those by 12 and 7 are two shifts and an or.
    #
    # Registers: r8 the state, r10 input, r11 output, rcx groups left, edx
    # the counter, eax a counter word, rax the constants; xmm0 to xmm11 the
    # rows of the three blocks, xmm12 and xmm13 scratch, xmm14 and xmm15 the
    # masks of the rotations by 16 and 8.
    macro xor_chacha20_keystream(state, input, output, group_count)
      {% template = "  mov $0, %r8\n  mov $1, %r10\n  mov $2, %r11\n  mov $3, %rcx
  lea 8f(%rip), %rax
  movdqu (%rax), %xmm14
  movdqu 16(%rax), %xmm15
  mov 48(%r8), %edx
1:
" %}
      {% for block in 0...3 %}
        {% for row in 0...4 %}
          {% template = template + "  movdqu #{row * 16}(%r8), %xmm#{block * 4 + row}\n" %}
        {% end %}
        {% template = template + "  lea #{block}(%rdx), %eax\n  pinsrd $$0, %eax, %xmm#{block * 4 + 3}\n" %}
      {% end %}
      {% for double_round in 0...10 %}
        {% for half in 0...2 %}
          {% for step in [[0, 1, 3, 16], [2, 3, 1, 12], [0, 1, 3, 8], [2, 3, 1, 7]] %}
            {% for block in 0...3 %}
              {% template = template + "  paddd %xmm#{block * 4 + step[1]}, %xmm#{block * 4 + step[0]}\n" %}
            {% end %}
            {% for block in 0...3 %}
              {% template = template + "  pxor %xmm#{block * 4 + step[0]}, %xmm#{block * 4 + step[2]}\n" %}
            {% end %}
            {% for block in 0...3 %}
              {% target = "%xmm#{block * 4 + step[2]}" %}
              {% if step[3] == 16 %}
                {% template = template + "  pshufb %xmm14, #{target.id}\n" %}
              {% elsif step[3] == 8 %}
                {% template = template + "  pshufb %xmm15, #{target.id}\n" %}
              {% else %}
                {% scratch = "%xmm#{12 + block % 2}" %}
                {% template = template + "  movdqa #{target.id}, #{scratch.id}\n  pslld $$#{step[3]}, #{target.id}\n  psrld $$#{32 - step[3]}, #{scratch.id}\n  por #{scratch.id}, #{target.id}\n" %}
              {% end %}
            {% end %}
          {% end %}
          {% for block in 0...3 %}
            {% if half == 0 %}
              {% template = template + "  pshufd $$0x39, %xmm#{block * 4 + 1}, %xmm#{block * 4 + 1}\n  pshufd $$0x4e, %xmm#{block * 4 + 2}, %xmm#{block * 4 + 2}\n  pshufd $$0x93, %xmm#{block * 4 + 3}, %xmm#{block * 4 + 3}\n" %}
            {% else %}
              {% template = template + "  pshufd $$0x93, %xmm#{block * 4 + 1}, %xmm#{block * 4 + 1}\n  pshufd $$0x4e, %xmm#{block * 4 + 2}, %xmm#{block * 4 + 2}\n  pshufd $$0x39, %xmm#{block * 4 + 3}, %xmm#{block * 4 + 3}\n" %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
      {% for block in 0...3 %}
        {% for row in 0...4 %}
          {% template = template + "  movdqu #{row * 16}(%r8), %xmm12\n" %}
          {% if row == 3 %}
            {% template = template + "  lea #{block}(%rdx), %eax\n  pinsrd $$0, %eax, %xmm12\n" %}
          {% end %}
          {% template = template + "  paddd %xmm12, %xmm#{block * 4 + row}
  movdqu #{block * 64 + row * 16}(%r10), %xmm13
  pxor %xmm13, %xmm#{block * 4 + row}
  movdqu %xmm#{block * 4 + row}, #{block * 64 + row * 16}(%r11)
" %}
        {% end %}
      {% end %}
      {% template = template + "  add $$3, %edx\n  add $$192, %r10\n  add $$192, %r11\n  dec %rcx\n  jnz 1b\n  mov %edx, 48(%r8)
  jmp 9f
  .p2align 4
8:
  .quad 0x0504070601000302
  .quad 0x0d0c0f0e09080b0a
  .quad 0x0605040702010003
  .quad 0x0e0d0c0f0a09080b
9:
" %}
      asm({{ template }} :: "r"({{ state }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }})
        : "rax", "rcx", "rdx", "r8", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "cc")
    end
  end
end
