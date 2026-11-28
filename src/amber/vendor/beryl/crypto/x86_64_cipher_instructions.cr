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
  # Statements that write the flags (`add`, `dec`) name the x86-64 flags
  # clobber "flags"; LLVM ignores "cc" on x86-64 (see
  # `FieldArithmetic::FieldsInAssembly`).
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
  #
  # Where the processor has VAES and VPCLMULQDQ (`ProcessorFeatures`), the
  # `_with_vector_*` macros run the same AES rounds and the same carry-less
  # multiplies on 256-bit registers (two blocks in each, AVX2) or on 512-bit
  # registers (four blocks in each, AVX-512), one instruction for all the
  # blocks of a register. They are written in the VEX and EVEX encodings
  # only, three operands and no alignment demand on a memory operand, and
  # end with `vzeroupper`, so the legacy SSE code around them never pays for
  # a dirty upper half. On these registers the GHASH product is the
  # schoolbook one (four carry-less multiplies, no Karatsuba operand), the
  # products of all the blocks of a group are summed lane by lane, each
  # lane is reduced with two carry-less multiplies
  # (`VECTOR_LANE_REDUCTION_LINES`), and the lanes are summed.
  #
  # The table of hash key powers has two parts:
  #
  # - bytes 0 to 511, for the AES-NI code: `HASH_KEY_POWER_COUNT` entries of
  #   `HASH_KEY_POWER_BYTESIZE` bytes, entry j holding H^(16 - j) twisted and
  #   then its Karatsuba operand;
  # - bytes 512 to 1023 (`VECTOR_HASH_KEY_POWERS_OFFSET`), for the vector
  #   code: `VECTOR_HASH_KEY_POWER_COUNT` entries of 16 bytes, entry j
  #   holding H^(32 - j) twisted, so that one load of 32 or 64 bytes fills
  #   the lanes of a register with the powers of consecutive blocks, the
  #   first block in the lowest lane.
  module X8664CipherInstructions
    # Bytes in one table entry of hash key powers: the twisted power, then
    # the exclusive or of its two 64-bit halves in both halves (the middle
    # operand of the Karatsuba multiply).
    HASH_KEY_POWER_BYTESIZE = 32

    # Powers of the hash key kept: H to H^16, one per block of a group.
    HASH_KEY_POWER_COUNT = 16

    # Where the vector code's part of the table starts.
    VECTOR_HASH_KEY_POWERS_OFFSET = HASH_KEY_POWER_BYTESIZE * HASH_KEY_POWER_COUNT

    # Powers of the hash key the vector code keeps: H to H^32, one per block
    # of its group.
    VECTOR_HASH_KEY_POWER_COUNT = 32

    # Bytes of the whole table, both parts.
    HASH_KEY_POWERS_BYTESIZE = VECTOR_HASH_KEY_POWERS_OFFSET + 16 * VECTOR_HASH_KEY_POWER_COUNT

    # The constants the vector statements read after their code: the mask
    # that reverses sixteen bytes (offset 0); the mask that reverses only the
    # last four, the counter word (16); the numbers 0, 1, 2 and 3 in the last
    # word of four blocks, the offsets of the lanes' counters (32); 4 (96)
    # and 2 (112) in the last word, the step of a register's counters; and
    # four copies of the reduction constant of `CONSTANT_LINES`, 0xc2 in the
    # highest byte, one for each lane (128).
    VECTOR_CONSTANT_LINES = "  jmp 9f\n  .p2align 6\n8:
  .quad 0x08090a0b0c0d0e0f\n  .quad 0x0001020304050607
  .quad 0x0706050403020100\n  .quad 0x0c0d0e0f0b0a0908
  .quad 0x0000000000000000\n  .quad 0x0000000000000000
  .quad 0x0000000000000000\n  .quad 0x0000000100000000
  .quad 0x0000000000000000\n  .quad 0x0000000200000000
  .quad 0x0000000000000000\n  .quad 0x0000000300000000
  .quad 0x0000000000000000\n  .quad 0x0000000400000000
  .quad 0x0000000000000000\n  .quad 0x0000000200000000
  .quad 0x0000000000000001\n  .quad 0xc200000000000000
  .quad 0x0000000000000001\n  .quad 0xc200000000000000
  .quad 0x0000000000000001\n  .quad 0xc200000000000000
  .quad 0x0000000000000001\n  .quad 0xc200000000000000
9:
"

    # The constants each statement reads after its code: the mask that
    # reverses sixteen bytes, then the twisting polynomial (1 in the lowest
    # byte, 0xc2 in the highest).
    CONSTANT_LINES = "  jmp 9f\n  .p2align 4\n8:\n  .quad 0x08090a0b0c0d0e0f\n  .quad 0x0001020304050607\n  .quad 0x0000000000000001\n  .quad 0xc200000000000000\n9:\n"

    # The constants of the aligned counters of
    # `encrypt_counter_blocks_and_hash_with_vector_aes`: for each of the
    # 32 blocks of a pass, its offset from the pass's first counter in the
    # last byte of a block (0 to 511), then 32 in the counter word, the step
    # of a pass (512).
    ALIGNED_COUNTER_CONSTANT_LINES = "  jmp 9f\n  .p2align 6\n7:
  .quad 0x0000000000000000\n  .quad 0x0000000000000000
  .quad 0x0000000000000000\n  .quad 0x0100000000000000
  .quad 0x0000000000000000\n  .quad 0x0200000000000000
  .quad 0x0000000000000000\n  .quad 0x0300000000000000
  .quad 0x0000000000000000\n  .quad 0x0400000000000000
  .quad 0x0000000000000000\n  .quad 0x0500000000000000
  .quad 0x0000000000000000\n  .quad 0x0600000000000000
  .quad 0x0000000000000000\n  .quad 0x0700000000000000
  .quad 0x0000000000000000\n  .quad 0x0800000000000000
  .quad 0x0000000000000000\n  .quad 0x0900000000000000
  .quad 0x0000000000000000\n  .quad 0x0a00000000000000
  .quad 0x0000000000000000\n  .quad 0x0b00000000000000
  .quad 0x0000000000000000\n  .quad 0x0c00000000000000
  .quad 0x0000000000000000\n  .quad 0x0d00000000000000
  .quad 0x0000000000000000\n  .quad 0x0e00000000000000
  .quad 0x0000000000000000\n  .quad 0x0f00000000000000
  .quad 0x0000000000000000\n  .quad 0x1000000000000000
  .quad 0x0000000000000000\n  .quad 0x1100000000000000
  .quad 0x0000000000000000\n  .quad 0x1200000000000000
  .quad 0x0000000000000000\n  .quad 0x1300000000000000
  .quad 0x0000000000000000\n  .quad 0x1400000000000000
  .quad 0x0000000000000000\n  .quad 0x1500000000000000
  .quad 0x0000000000000000\n  .quad 0x1600000000000000
  .quad 0x0000000000000000\n  .quad 0x1700000000000000
  .quad 0x0000000000000000\n  .quad 0x1800000000000000
  .quad 0x0000000000000000\n  .quad 0x1900000000000000
  .quad 0x0000000000000000\n  .quad 0x1a00000000000000
  .quad 0x0000000000000000\n  .quad 0x1b00000000000000
  .quad 0x0000000000000000\n  .quad 0x1c00000000000000
  .quad 0x0000000000000000\n  .quad 0x1d00000000000000
  .quad 0x0000000000000000\n  .quad 0x1e00000000000000
  .quad 0x0000000000000000\n  .quad 0x1f00000000000000
  .quad 0x0000000000000000\n  .quad 0x0000002000000000
9:
"

    # Reduces, lane by lane, the 256-bit products whose low, middle and high
    # 128-bit parts are summed in `@LO`, `@MI` and `@HI` (the full product
    # being HI x^128 + MI x^64 + LO), leaving the result in `@HI`, with `@T`
    # as scratch; `@C` is a register or memory operand holding the reduction
    # constant in the high 64 bits of each lane. This is `REDUCTION_LINES`
    # written with carry-less multiplies: the left shifts by 57, 62 and 63
    # there are the low half of a multiply by that constant, the right
    # shifts by 1, 2 and 7 its high half, so two multiplies (each folding
    # 64 bits) and two swaps of halves replace the twenty shifts and
    # exclusive ors, and the middle part folds in on the way (the method of
    # Linux's `aes-gcm-avx10-x86_64.S`). `@X3` names the three-way
    # exclusive or (`vpternlogq $$0x96`, or two `vpxor`). Linear, so the
    # lanes can be summed after it.
    VECTOR_LANE_REDUCTION_LINES = "  vpclmulqdq $$0x10, @C, @LO, @T
  vpshufd $$0x4e, @LO, @LO
@X3(@T, @LO, @MI)  vpclmulqdq $$0x10, @C, @MI, @T
  vpshufd $$0x4e, @MI, @MI
@X3(@T, @MI, @HI)"

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
    # (`HASH_KEY_POWERS_BYTESIZE` bytes, both parts described above) from
    # the hash key at *hash_key* (16 bytes, the encryption of the zero
    # block). The highest power comes first in each part: entry j of the
    # first holds H^(16 - j) and entry j of the second H^(32 - j), so that n
    # blocks hashed together take the n entries from 16 - n (or 32 - n) on.
    # No loop: thirty-one multiplies written out.
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
  movdqu %xmm3, 1008(%r9)
  movdqa %xmm3, %xmm0
" %}
      {% for power in 2..32 %}
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
" + ::Amber::Beryl::Crypto::X8664CipherInstructions::REDUCTION_LINES.gsub(/@L/, "%xmm0").gsub(/@H/, "%xmm1").gsub(/@A/, "%xmm5").gsub(/@B/, "%xmm6") + "  movdqu %xmm0, #{512 + (32 - power) * 16}(%r9)\n" %}
        {% if power <= 16 %}
          {% template = template + "  pshufd $$0x4e, %xmm0, %xmm2
  pxor %xmm0, %xmm2
  movdqu %xmm0, #{(16 - power) * 32}(%r9)
  movdqu %xmm2, #{(16 - power) * 32 + 16}(%r9)
" %}
        {% end %}
      {% end %}
      {% template = template + ::Amber::Beryl::Crypto::X8664CipherInstructions::CONSTANT_LINES %}
      asm({{ template }} :: "r"({{ hash_key }}), "r"({{ hash_key_powers }})
        : "rax", "r8", "r9", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "memory", "flags")
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
      {% reduction = ::Amber::Beryl::Crypto::X8664CipherInstructions::REDUCTION_LINES.gsub(/@L/, "%xmm11").gsub(/@H/, "%xmm12").gsub(/@A/, "%xmm1").gsub(/@B/, "%xmm2") %}
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
      {% template = template + "  movdqu %xmm14, (%r8)\n" + ::Amber::Beryl::Crypto::X8664CipherInstructions::CONSTANT_LINES %}
      asm({{ template }} :: "r"({{ accumulator }}), "r"({{ first_hash_key_power }}), "r"({{ input }}), "r"({{ group_count }})
        : "rax", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "flags")
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
          "xmm10", "xmm11", "xmm12", "memory", "flags")
    end

    # Counter mode on VAES: what `encrypt_counter_blocks` does, with the
    # blocks of a register going through each round in one instruction.
    # *register_bitsize* is 512 (zmm registers, four blocks each, AVX-512) or
    # 256 (ymm registers, two blocks each). Each pass encrypts
    # *registers_per_group* registers of blocks (8 or 1), *group_count*
    # passes (at least 1); with eight, the processor always has eight
    # independent AES instructions to start.
    #
    # The counters are kept with their last word in the processor's byte
    # order, so that `vpaddd` steps every lane's counter at once and wraps
    # it at 2^32 as SP 800-38D's inc32 does; one `vpshufb` per register puts
    # the word back in big-endian order before the first round.
    #
    # Registers: r8 round keys, r9 counter block, r10 input, r11 output, rcx
    # passes left, rax constants; 0 to 7 the blocks, 8 a round key, 9 a
    # message register, 10 the last round key, 11 the counters of the next
    # register, 12 the step between registers, 13 the mask that reverses the
    # counter word, 14 the first round key. As in `encrypt_counter_blocks`,
    # the message is XORed into the last round key.
    macro encrypt_counter_blocks_with_vector_aes(round_keys, counter_block, input, output, group_count, round_count, register_bitsize, registers_per_group)
      {% vector = register_bitsize == 512 ? "zmm" : "ymm" %}
      {% register_bytesize = register_bitsize // 8 %}
      {% broadcast = register_bitsize == 512 ? "vbroadcasti32x4" : "vbroadcasti128" %}
      {% exclusive_or = register_bitsize == 512 ? "vpxord" : "vpxor" %}
      {% move = register_bitsize == 512 ? "vmovdqu64" : "vmovdqu" %}
      {% step_offset = register_bitsize == 512 ? 96 : 112 %}
      {% template = "  mov $0, %r8\n  mov $1, %r9\n  mov $2, %r10\n  mov $3, %r11\n  mov $4, %rcx
  lea 8f(%rip), %rax
  #{broadcast.id} 16(%rax), %#{vector.id}13
  #{broadcast.id} (%r9), %#{vector.id}11
  vpshufb %#{vector.id}13, %#{vector.id}11, %#{vector.id}11
  vpaddd 32(%rax), %#{vector.id}11, %#{vector.id}11
  #{broadcast.id} #{step_offset}(%rax), %#{vector.id}12
  #{broadcast.id} (%r8), %#{vector.id}14
  #{broadcast.id} #{round_count * 16}(%r8), %#{vector.id}10
1:
" %}
      {% for register in 0...registers_per_group %}
        {% template = template + "  vpshufb %#{vector.id}13, %#{vector.id}11, %#{vector.id}#{register}
  vpaddd %#{vector.id}12, %#{vector.id}11, %#{vector.id}11
  #{exclusive_or.id} %#{vector.id}14, %#{vector.id}#{register}, %#{vector.id}#{register}
" %}
      {% end %}
      {% for round in 1...round_count %}
        {% template = template + "  #{broadcast.id} #{round * 16}(%r8), %#{vector.id}8\n" %}
        {% for register in 0...registers_per_group %}
          {% template = template + "  vaesenc %#{vector.id}8, %#{vector.id}#{register}, %#{vector.id}#{register}\n" %}
        {% end %}
      {% end %}
      {% for register in 0...registers_per_group %}
        {% template = template + "  #{move.id} #{register * register_bytesize}(%r10), %#{vector.id}9
  #{exclusive_or.id} %#{vector.id}10, %#{vector.id}9, %#{vector.id}9
  vaesenclast %#{vector.id}9, %#{vector.id}#{register}, %#{vector.id}#{register}
  #{move.id} %#{vector.id}#{register}, #{register * register_bytesize}(%r11)
" %}
      {% end %}
      {% template = template + "  add $$#{registers_per_group * register_bytesize}, %r10
  add $$#{registers_per_group * register_bytesize}, %r11
  dec %rcx
  jnz 1b
  vpshufb %xmm13, %xmm11, %xmm11
  vmovdqu %xmm11, (%r9)
  vzeroupper
" + ::Amber::Beryl::Crypto::X8664CipherInstructions::VECTOR_CONSTANT_LINES %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ counter_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }})
        : "rax", "rcx", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "memory", "flags")
    end

    # Counter mode and GHASH in one loop on 512-bit registers (the stitched
    # arrangement of OpenSSL's `aes-gcm-avx512` and Linux's
    # `aes-gcm-avx10-x86_64.S`): each of *group_count* passes (at least 1)
    # encrypts 32 counter blocks as `encrypt_counter_blocks_with_vector_aes`
    # does with eight registers, and between its AES rounds hashes 32 blocks
    # into the accumulator at *accumulator* as
    # `absorb_hash_blocks_with_vector_carryless_multiply` does in groups
    # (*hash_key_powers* is the vector part of the table): the ciphertext
    # the pass before wrote, the 512 bytes before *output* (a seal), or
    # with *is_hashing_input* the pass's own 512 bytes of *input* (an
    # opening; every load of a pass comes before its stores, so *output* may
    # be *input*). The AES rounds and the carry-less multiplies go to
    # different execution ports, so the two overlap; the AES and GHASH sides
    # share no register. The nine pieces of hash work (eight registers, then
    # the reduction) are spread evenly over the rounds before the last (after
    # rounds 1 to 9 for AES-128, 1, 2, 4, 5, 7, 8, 10, 11 and 13 for
    # AES-256), so that the shared port never has more work in a stretch
    # than the AES port has rounds to cover it. The first register of the
    # group is hashed last, since it alone waits for the accumulator the
    # pass before left.
    #
    # With *is_counter_aligned*, the caller guarantees that the counter word
    # of the counter block is a multiple of 32 when the loop starts (a
    # 12-byte nonce, whose first message counter is 2, after 30 blocks), so
    # the 32 counters of a pass differ from the first only in the low five
    # bits of the last byte: each block is the first counter block, already
    # XORed with the first round key, XORed with its offset (one
    # instruction a register instead of a shuffle, an add and an XOR), and
    # the counter word is byte-swapped and stepped once a pass. The
    # alignment is a fact about positions in the message, not about its
    # contents, and the statement still has its one branch.
    #
    # Registers: r10 input, r11 output, rcx passes left; the round keys, the
    # counter block, the accumulator and the hash key powers are read where
    # the operands put them, and the constants relative to rip. zmm0 to
    # zmm14 as in `encrypt_counter_blocks_with_vector_aes`; zmm15 the mask
    # that reverses sixteen bytes, zmm16 a register of blocks to hash, zmm17
    # its powers, zmm18 to zmm21 the partial products, zmm22 to zmm24 their
    # sums, xmm25 the accumulator, zmm26 and zmm27 scratch. Registers 16 and
    # up exist only in the EVEX encoding, so that side writes `vpxorq` and
    # `vmovdqu64`.
    macro encrypt_counter_blocks_and_hash_with_vector_aes(round_keys, counter_block, input, output, group_count, round_count, accumulator, hash_key_powers, is_hashing_input = false, is_counter_aligned = false)
      {% template = "  mov $2, %r10\n  mov $3, %r11\n  mov $4, %rcx
  vbroadcasti32x4 8f+16(%rip), %zmm13
  vbroadcasti32x4 ($1), %zmm11
  vpshufb %zmm13, %zmm11, %zmm11
" %}
      {% if is_counter_aligned %}
        {% template = template + "  vbroadcasti32x4 7f+512(%rip), %zmm12\n" %}
      {% else %}
        {% template = template + "  vpaddd 8f+32(%rip), %zmm11, %zmm11\n  vbroadcasti32x4 8f+96(%rip), %zmm12\n" %}
      {% end %}
      {% template = template + "
  vbroadcasti32x4 ($0), %zmm14
  vbroadcasti32x4 #{round_count * 16}($0), %zmm10
  vbroadcasti32x4 8f(%rip), %zmm15
  vmovdqu64 ($5), %xmm25
1:
" %}
      {% if is_counter_aligned %}
        {% template = template + "  vpshufb %zmm13, %zmm11, %zmm9\n  vpxord %zmm14, %zmm9, %zmm9\n  vpaddd %zmm12, %zmm11, %zmm11\n" %}
        {% for register in 0...8 %}
          {% template = template + "  vpxord 7f+#{register * 64}(%rip), %zmm9, %zmm#{register}\n" %}
        {% end %}
      {% else %}
        {% for register in 0...8 %}
          {% template = template + "  vpshufb %zmm13, %zmm11, %zmm#{register}
  vpaddd %zmm12, %zmm11, %zmm11
  vpxord %zmm14, %zmm#{register}, %zmm#{register}
" %}
        {% end %}
      {% end %}
      {% list_of_hash_lines = [] of String %}
      {% for register, position in [1, 2, 3, 4, 5, 6, 7, 0] %}
        {% set = position % 2 == 0 ? [16, 17, 18, 19, 20, 21] : [26, 27, 28, 29, 30, 31] %}
        {% hash_source = is_hashing_input ? "#{register * 64}(%r10)" : "#{register * 64 - 512}(%r11)" %}
        {% lines = "  vmovdqu64 #{hash_source.id}, %zmm#{set[0]}\n  vpshufb %zmm15, %zmm#{set[0]}, %zmm#{set[0]}\n" %}
        {% if register == 0 %}
          {% lines = lines + "  vpxorq %zmm25, %zmm#{set[0]}, %zmm#{set[0]}\n" %}
        {% end %}
        {% lines = lines + "  vmovdqu64 #{register * 64}($6), %zmm#{set[1]}
  vpclmulqdq $$0x00, %zmm#{set[1]}, %zmm#{set[0]}, %zmm#{set[2]}
  vpclmulqdq $$0x11, %zmm#{set[1]}, %zmm#{set[0]}, %zmm#{set[3]}
  vpclmulqdq $$0x01, %zmm#{set[1]}, %zmm#{set[0]}, %zmm#{set[4]}
  vpclmulqdq $$0x10, %zmm#{set[1]}, %zmm#{set[0]}, %zmm#{set[5]}
" %}
        {% if position == 1 %}
          {% lines = lines + "  vpxorq %zmm28, %zmm18, %zmm22\n  vpxorq %zmm29, %zmm19, %zmm23\n  vpternlogq $$0x96, %zmm21, %zmm20, %zmm30\n  vpxorq %zmm31, %zmm30, %zmm24\n" %}
        {% elsif position % 2 == 1 %}
          {% lines = lines + "  vpternlogq $$0x96, %zmm28, %zmm18, %zmm22\n  vpternlogq $$0x96, %zmm29, %zmm19, %zmm23\n  vpternlogq $$0x96, %zmm21, %zmm20, %zmm30\n  vpternlogq $$0x96, %zmm31, %zmm30, %zmm24\n" %}
        {% end %}
        {% list_of_hash_lines = list_of_hash_lines + [lines] %}
      {% end %}
      {% reduction_lines = ::Amber::Beryl::Crypto::X8664CipherInstructions::VECTOR_LANE_REDUCTION_LINES.gsub(/@X3\(@T, @LO, @MI\)/, "  vpternlogq $$0x96, %zmm16, %zmm22, %zmm24\n").gsub(/@X3\(@T, @MI, @HI\)/, "  vpternlogq $$0x96, %zmm16, %zmm24, %zmm23\n").gsub(/@C/, "8f+128(%rip)").gsub(/@LO/, "%zmm22").gsub(/@MI/, "%zmm24").gsub(/@HI/, "%zmm23").gsub(/@T/, "%zmm16") +
                           "  vextracti64x4 $$1, %zmm23, %ymm16\n  vpxorq %ymm16, %ymm23, %ymm23\n  vextracti32x4 $$1, %ymm23, %xmm16\n  vpxorq %xmm16, %xmm23, %xmm25\n" %}
      {% for round in 1...round_count %}
        {% template = template + "  vbroadcasti32x4 #{round * 16}($0), %zmm8\n" %}
        {% for register in 0...8 %}
          {% template = template + "  vaesenc %zmm8, %zmm#{register}, %zmm#{register}\n" %}
        {% end %}
        {% for chunk in 0..8 %}
          {% if round == 1 + chunk * (round_count - 2) // 8 %}
            {% template = template + (chunk < 8 ? list_of_hash_lines[chunk] : reduction_lines) %}
          {% end %}
        {% end %}
      {% end %}
      {% for register in 0...8 %}
        {% template = template + "  vmovdqu64 #{register * 64}(%r10), %zmm9
  vpxord %zmm10, %zmm9, %zmm9
  vaesenclast %zmm9, %zmm#{register}, %zmm#{register}
  vmovdqu64 %zmm#{register}, #{register * 64}(%r11)
" %}
      {% end %}
      {% template = template + "  add $$512, %r10
  add $$512, %r11
  dec %rcx
  jnz 1b
  vpshufb %xmm13, %xmm11, %xmm11
  vmovdqu %xmm11, ($1)
  vmovdqu64 %xmm25, ($5)
  vzeroupper
" + ::Amber::Beryl::Crypto::X8664CipherInstructions::VECTOR_CONSTANT_LINES %}
      {% if is_counter_aligned %}
        {% template = template + ::Amber::Beryl::Crypto::X8664CipherInstructions::ALIGNED_COUNTER_CONSTANT_LINES %}
      {% end %}
      asm({{ template }} :: "r"({{ round_keys }}), "r"({{ counter_block }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }}),
        "r"({{ accumulator }}), "r"({{ hash_key_powers }})
        : "rcx", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "xmm16", "xmm17", "xmm18", "xmm19",
          "xmm20", "xmm21", "xmm22", "xmm23", "xmm24", "xmm25", "xmm26", "xmm27", "xmm28", "xmm29",
          "xmm30", "xmm31", "memory", "flags")
    end

    # GHASH on VPCLMULQDQ: what `absorb_hash_blocks` does, with the blocks of
    # a register multiplied by their powers in one instruction per partial
    # product. *register_bitsize* is 512 (four blocks a register) or 256
    # (two). *first_hash_key_power* points into the vector part of the table.
    #
    # - *is_grouped* true: *group_count* groups of 32 blocks, each multiplied
    #   by H^32 to H (the vector part from its first entry) and reduced once.
    # - *is_grouped* false: *group_count* registers of blocks (fewer than 32
    #   blocks in all), multiplied by the powers from the entry
    #   *first_hash_key_power* points at on, summed, and reduced once at the
    #   end. The accumulator joins the first register only.
    #
    # The accumulator joins the lowest lane of the first register of a
    # group: it sits in the low 128 bits of register 14 (or 10) and the VEX
    # instructions that write it clear the bits above.
    # In a group of 32 the first register is multiplied last, since it
    # alone waits for the accumulator the group before left.
    #
    # The sums are reduced lane by lane (`VECTOR_LANE_REDUCTION_LINES`) and
    # the lanes then summed into the accumulator.
    #
    # Registers: r8 the accumulator, r9 hash key powers, r10 input, r11
    # groups (or registers) left, rax constants; 0 a register of blocks, 1
    # its powers, 2 to 5 the four partial products, 11, 12 and 13 the sums
    # of the low, high and middle products, 14 the accumulator, 10 the
    # accumulator for the first register and zero after, 15 the mask that
    # reverses sixteen bytes.
    macro absorb_hash_blocks_with_vector_carryless_multiply(accumulator, first_hash_key_power, input, group_count, register_bitsize, is_grouped)
      {% vector = register_bitsize == 512 ? "zmm" : "ymm" %}
      {% register_bytesize = register_bitsize // 8 %}
      {% registers_per_group = is_grouped ? 4096 // register_bitsize : 1 %}
      {% broadcast = register_bitsize == 512 ? "vbroadcasti32x4" : "vbroadcasti128" %}
      {% exclusive_or = register_bitsize == 512 ? "vpxord" : "vpxor" %}
      {% move = register_bitsize == 512 ? "vmovdqu64" : "vmovdqu" %}
      {% template = "  mov $0, %r8\n  mov $1, %r9\n  mov $2, %r10\n  mov $3, %r11
  lea 8f(%rip), %rax
  #{broadcast.id} (%rax), %#{vector.id}15
  vmovdqu (%r8), %xmm14
" %}
      {% joined = is_grouped ? "14" : "10" %}
      {% register_lines = "" %}
      {% for position in 0...registers_per_group %}
        {% register = (position + 1) % registers_per_group %}
        {% register_lines = register_lines + "  #{move.id} #{register * register_bytesize}(%r10), %#{vector.id}0
  vpshufb %#{vector.id}15, %#{vector.id}0, %#{vector.id}0
" %}
        {% if register == 0 %}
          {% register_lines = register_lines + "  #{exclusive_or.id} %#{vector.id}#{joined.id}, %#{vector.id}0, %#{vector.id}0\n" %}
          {% if !is_grouped %}
            {% register_lines = register_lines + "  vpxor %xmm10, %xmm10, %xmm10\n" %}
          {% end %}
        {% end %}
        {% register_lines = register_lines + "  #{move.id} #{register * register_bytesize}(%r9), %#{vector.id}1
  vpclmulqdq $$0x00, %#{vector.id}1, %#{vector.id}0, %#{vector.id}2
  vpclmulqdq $$0x11, %#{vector.id}1, %#{vector.id}0, %#{vector.id}3
  vpclmulqdq $$0x01, %#{vector.id}1, %#{vector.id}0, %#{vector.id}4
  vpclmulqdq $$0x10, %#{vector.id}1, %#{vector.id}0, %#{vector.id}5
  #{exclusive_or.id} %#{vector.id}2, %#{vector.id}11, %#{vector.id}11
  #{exclusive_or.id} %#{vector.id}3, %#{vector.id}12, %#{vector.id}12
" %}
        {% if register_bitsize == 512 %}
          {% register_lines = register_lines + "  vpternlogq $$0x96, %zmm5, %zmm4, %zmm13\n" %}
        {% else %}
          {% register_lines = register_lines + "  vpxor %ymm4, %ymm13, %ymm13\n  vpxor %ymm5, %ymm13, %ymm13\n" %}
        {% end %}
      {% end %}
      {% three_way = register_bitsize == 512 ? "  vpternlogq $$0x96, @A, @B, @D\n" : "  vpxor @A, @D, @D\n  vpxor @B, @D, @D\n" %}
      {% folding_lines = ::Amber::Beryl::Crypto::X8664CipherInstructions::VECTOR_LANE_REDUCTION_LINES.gsub(/@X3\(@T, @LO, @MI\)/, three_way.gsub(/@A/, "@T").gsub(/@B/, "@LO").gsub(/@D/, "@MI")).gsub(/@X3\(@T, @MI, @HI\)/, three_way.gsub(/@A/, "@T").gsub(/@B/, "@MI").gsub(/@D/, "@HI")).gsub(/@C/, "128(%rax)").gsub(/@LO/, "%#{vector.id}11").gsub(/@MI/, "%#{vector.id}13").gsub(/@HI/, "%#{vector.id}12").gsub(/@T/, "%#{vector.id}2") %}
      {% if register_bitsize == 512 %}
        {% folding_lines = folding_lines + "  vextracti64x4 $$1, %zmm12, %ymm2\n  vpxor %ymm2, %ymm12, %ymm12\n" %}
      {% end %}
      {% folding_lines = folding_lines + "  vextracti128 $$1, %ymm12, %xmm2\n  vpxor %xmm2, %xmm12, %xmm14\n" %}
      {% zeroing_lines = "  vpxor %xmm11, %xmm11, %xmm11\n  vpxor %xmm12, %xmm12, %xmm12\n  vpxor %xmm13, %xmm13, %xmm13\n" %}
      {% if is_grouped %}
        {% template = template + "1:\n" + zeroing_lines + register_lines + folding_lines + "  add $$512, %r10\n  dec %r11\n  jnz 1b\n" %}
      {% else %}
        {% template = template + zeroing_lines + "  vmovdqa %xmm14, %xmm10\n1:\n" + register_lines + "  add $$#{register_bytesize}, %r10\n  add $$#{register_bytesize}, %r9\n  dec %r11\n  jnz 1b\n" + folding_lines %}
      {% end %}
      {% template = template + "  vmovdqu %xmm14, (%r8)\n  vzeroupper\n" + ::Amber::Beryl::Crypto::X8664CipherInstructions::VECTOR_CONSTANT_LINES %}
      asm({{ template }} :: "r"({{ accumulator }}), "r"({{ first_hash_key_power }}), "r"({{ input }}), "r"({{ group_count }})
        : "rax", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "flags")
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
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "flags")
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
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "memory", "flags")
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
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "flags")
    end

    # Blocks of ChaCha20 keystream one pass of
    # `xor_chacha20_keystream_on_256_bit_registers` produces.
    CHACHA20_BLOCKS_PER_256_BIT_GROUP = 8

    # ChaCha20 on AVX2, eight blocks a pass, with the parameters and meaning
    # of `xor_chacha20_keystream`; *scratch* is 256 bytes the statement keeps
    # words of the state in, which the caller wipes. With *key_block*, the
    # single pass writes block 0's keystream there (64 bytes) and XORs blocks
    # 1 to 7 into the message from its start.
    #
    # The state is laid out across the blocks (Goll and Gueron, "Vectorization
    # on ChaCha Stream Cipher", ITNG 2014, the arrangement of OpenSSL's
    # `ChaCha20_8x`): register i holds word i of all eight blocks, so a quarter
    # round is the scalar one on eight lanes, and the diagonal rounds need no
    # shuffles. Sixteen words fill the sixteen registers, and the rotations by
    # 12 and 7 need a scratch register each, so words 8 to 11 take turns: two
    # of them are in registers and two in *scratch*, and two quarter rounds run
    # at a time. The columns (0, 1) and the diagonals (2, 3) use words 8 and 9,
    # the columns (2, 3) and the diagonals (0, 1) words 10 and 11, so the pair
    # changes twice a double round. At the end the words are transposed into
    # blocks with `vpunpck*dq` and `vperm2i128`.
    #
    # Registers: r8 the state, r9 scratch, r10 input, r11 output, rcx groups
    # left, edx the counter, r12 the key block; ymm0 to ymm7 and ymm12 to
    # ymm15 words 0 to 7 and 12 to 15, ymm8 and ymm9 the two of words 8 to 11
    # in registers, ymm10 and ymm11 scratch.
    #
    # `xor_chacha20_keystream_absorbing_poly1305` builds its statement here
    # too (*absorbing* "seal" or "open"): see there.
    macro xor_chacha20_keystream_on_256_bit_registers(state, scratch, input, output, group_count, key_block = nil, absorbing = nil)
      {% shift = key_block.is_a?(NilLiteral) ? 0 : 64 %}
      {% is_absorbing = !absorbing.is_a?(NilLiteral) %}
      {% if is_absorbing %}
        {% word_operands = (0...16).map { |word| "#{256 + word * 4}($0)" } %}
        {% scratch_base = "($0)" %}
        {% counter = "%r12d" %}
        {% template = "  mov $1, %rcx\n  mov 368($0), %r10\n  mov 376($0), %r11\n  mov 304($0), %r12d\n  mov 320($0), %r13\n  mov 328($0), %r14\n  mov 336($0), %r15\n1:\n" %}
      {% else %}
        {% word_operands = (0...16).map { |word| "#{word * 4}(%r8)" } %}
        {% scratch_base = "(%r9)" %}
        {% counter = "%edx" %}
        {% template = "  mov $0, %r8\n  mov $1, %r9\n  mov $2, %r10\n  mov $3, %r11\n  mov $4, %rcx\n  mov 48(%r8), %edx\n1:\n" %}
      {% end %}
      {% for word in 0...16 %}
        {% if word == 12 %}
          {% template = template + "  vmovd #{counter.id}, %xmm12\n  vpbroadcastd %xmm12, %ymm12\n  vpaddd 6f(%rip), %ymm12, %ymm12\n" %}
        {% elsif word == 10 || word == 11 %}
          {% template = template + "  vpbroadcastd #{word_operands[word].id}, %ymm10\n  vmovdqu %ymm10, #{(word - 8) * 32}#{scratch_base.id}\n" %}
        {% else %}
          {% template = template + "  vpbroadcastd #{word_operands[word].id}, %ymm#{word}\n" %}
        {% end %}
      {% end %}
      # Each pair lists two quarter rounds as the registers of their a, b, c
      # and d; a swap stores the two words 8 to 11 in registers and loads the
      # other two.
      {% swap_to_high = "  vmovdqu %ymm8, #{scratch_base.id}\n  vmovdqu %ymm9, 32#{scratch_base.id}\n  vmovdqu 64#{scratch_base.id}, %ymm8\n  vmovdqu 96#{scratch_base.id}, %ymm9\n" %}
      {% swap_to_low = "  vmovdqu %ymm8, 64#{scratch_base.id}\n  vmovdqu %ymm9, 96#{scratch_base.id}\n  vmovdqu #{scratch_base.id}, %ymm8\n  vmovdqu 32#{scratch_base.id}, %ymm9\n" %}
      {% double_round = "" %}
      {% for pair in [[[0, 4, 8, 12], [1, 5, 9, 13]], "high", [[2, 6, 8, 14], [3, 7, 9, 15]], [[0, 5, 8, 15], [1, 6, 9, 12]], "low", [[2, 7, 8, 13], [3, 4, 9, 14]]] %}
        {% if pair == "high" %}
          {% double_round = double_round + swap_to_high %}
        {% elsif pair == "low" %}
          {% double_round = double_round + swap_to_low %}
        {% else %}
          {% for step in [[0, 1, 3, 16], [2, 3, 1, 12], [0, 1, 3, 8], [2, 3, 1, 7]] %}
            {% for quarter in pair %}
              {% double_round = double_round + "  vpaddd %ymm#{quarter[step[1]]}, %ymm#{quarter[step[0]]}, %ymm#{quarter[step[0]]}\n" %}
            {% end %}
            {% for quarter in pair %}
              {% double_round = double_round + "  vpxor %ymm#{quarter[step[0]]}, %ymm#{quarter[step[2]]}, %ymm#{quarter[step[2]]}\n" %}
            {% end %}
            {% for quarter, position in pair %}
              {% target = "%ymm#{quarter[step[2]]}" %}
              {% if step[3] == 16 %}
                {% double_round = double_round + "  vpshufb 8f(%rip), #{target.id}, #{target.id}\n" %}
              {% elsif step[3] == 8 %}
                {% double_round = double_round + "  vpshufb 7f(%rip), #{target.id}, #{target.id}\n" %}
              {% else %}
                {% spare = "%ymm#{10 + position}" %}
                {% double_round = double_round + "  vpsrld $$#{32 - step[3]}, #{target.id}, #{spare.id}\n  vpslld $$#{step[3]}, #{target.id}, #{target.id}\n  vpor #{spare.id}, #{target.id}, #{target.id}\n" %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
      {% rounds = "" %}
      {% for index in 0...10 %}
        {% rounds = rounds + double_round %}
      {% end %}
      # Absorbing, the Poly1305 blocks of the pass are spread evenly through
      # the rounds, but for those of the bytes this pass writes itself,
      # which follow its stores.
      {% late_poly1305 = "" %}
      {% if is_absorbing %}
        {% list_of_round_lines = rounds.split("\n").reject { |line| line.empty? } %}
        {% list_of_poly1305_lines = [] of String %}
        {% for block in 0...32 %}
          {% if absorbing == "seal" %}
            {% low_word = "#{block * 16 - 448}(%r11)" %}
            {% high_word = "#{block * 16 - 440}(%r11)" %}
          {% else %}
            {% low_word = "#{block * 16}(%r10)" %}
            {% high_word = "#{block * 16 + 8}(%r10)" %}
          {% end %}
          {% lines = ::Amber::Beryl::Crypto::X8664CipherInstructions::POLY1305_BLOCK_LINES.gsub(/@M/, low_word).gsub(/@N/, high_word) %}
          {% if absorbing == "seal" && block >= 28 %}
            {% late_poly1305 = late_poly1305 + lines %}
          {% else %}
            {% list_of_poly1305_lines = list_of_poly1305_lines + lines.split("\n").reject { |line| line.empty? } %}
          {% end %}
        {% end %}
        {% rounds = "" %}
        {% emitted = 0 %}
        {% for line, index in list_of_round_lines %}
          {% rounds = rounds + line + "\n" %}
          {% target = ((index + 1) * list_of_poly1305_lines.size) // list_of_round_lines.size %}
          {% if target > emitted %}
            {% for poly1305_line in list_of_poly1305_lines[emitted...target] %}
              {% rounds = rounds + poly1305_line + "\n" %}
            {% end %}
            {% emitted = target %}
          {% end %}
        {% end %}
      {% end %}
      {% template = template + rounds %}
      # Words 8 and 9 are in registers again: words 8 to 15 go to scratch,
      # and the two halves of the words are added to the state, transposed
      # and XORed into the message one after the other.
      {% for register in [8, 9, 12, 13, 14, 15] %}
        {% template = template + "  vmovdqu %ymm#{register}, #{(register - 8) * 32}#{scratch_base.id}\n" %}
      {% end %}
      {% for half in 0...2 %}
        {% if half == 1 %}
          {% for register in 0...8 %}
            {% template = template + "  vmovdqu #{register * 32}#{scratch_base.id}, %ymm#{register}\n" %}
          {% end %}
        {% end %}
        {% for register in 0...8 %}
          {% word = half * 8 + register %}
          {% if word == 12 %}
            {% template = template + "  vmovd #{counter.id}, %xmm8\n  vpbroadcastd %xmm8, %ymm8\n  vpaddd 6f(%rip), %ymm8, %ymm8\n" %}
          {% else %}
            {% template = template + "  vpbroadcastd #{word_operands[word].id}, %ymm8\n" %}
          {% end %}
          {% template = template + "  vpaddd %ymm8, %ymm#{register}, %ymm#{register}\n" %}
        {% end %}
        # Each four words transpose into four registers that hold blocks k
        # and k + 4 (k = 0 to 3) in their two halves.
        {% list_of_block_registers = [] of String %}
        {% for quad in 0...2 %}
          {% a = "%ymm#{quad * 4}" %}
          {% b = "%ymm#{quad * 4 + 1}" %}
          {% c = "%ymm#{quad * 4 + 2}" %}
          {% d = "%ymm#{quad * 4 + 3}" %}
          {% t = "%ymm#{8 + quad}" %}
          {% template = template + "  vpunpckldq #{b.id}, #{a.id}, #{t.id}
  vpunpckhdq #{b.id}, #{a.id}, #{b.id}
  vpunpckldq #{d.id}, #{c.id}, #{a.id}
  vpunpckhdq #{d.id}, #{c.id}, #{d.id}
  vpunpcklqdq #{a.id}, #{t.id}, #{c.id}
  vpunpckhqdq #{a.id}, #{t.id}, #{t.id}
  vpunpcklqdq #{d.id}, #{b.id}, #{a.id}
  vpunpckhqdq #{d.id}, #{b.id}, #{b.id}
" %}
          {% list_of_block_registers = list_of_block_registers + [c, t, a, b] %}
        {% end %}
        {% for block in 0...4 %}
          {% first = list_of_block_registers[block] %}
          {% second = list_of_block_registers[4 + block] %}
          {% template = template + "  vperm2i128 $$0x20, #{second.id}, #{first.id}, %ymm10\n  vperm2i128 $$0x31, #{second.id}, #{first.id}, %ymm11\n" %}
          {% if shift > 0 && block == 0 %}
            {% template = template + "  vmovdqu %ymm10, #{half * 32}(%r12)\n" %}
          {% else %}
            {% template = template + "  vpxor #{block * 64 + half * 32 - shift}(%r10), %ymm10, %ymm10\n  vmovdqu %ymm10, #{block * 64 + half * 32 - shift}(%r11)\n" %}
          {% end %}
          {% template = template + "  vpxor #{(block + 4) * 64 + half * 32 - shift}(%r10), %ymm11, %ymm11\n  vmovdqu %ymm11, #{(block + 4) * 64 + half * 32 - shift}(%r11)\n" %}
        {% end %}
      {% end %}
      {% template = template + late_poly1305 + "  add $$8, #{counter.id}\n  add $$512, %r10\n  add $$512, %r11\n  dec %rcx\n  jnz 1b\n" %}
      {% if is_absorbing %}
        {% template = template + "  mov %r12d, 304($0)\n  mov %r13, 320($0)\n  mov %r14, 328($0)\n  mov %r15, 336($0)\n" %}
      {% else %}
        {% template = template + "  mov %edx, 48(%r8)\n" %}
      {% end %}
      {% template = template + "  vzeroupper
  jmp 9f
  .p2align 5
6:
  .long 0, 1, 2, 3, 4, 5, 6, 7
7:
  .quad 0x0605040702010003
  .quad 0x0e0d0c0f0a09080b
  .quad 0x0605040702010003
  .quad 0x0e0d0c0f0a09080b
8:
  .quad 0x0504070601000302
  .quad 0x0d0c0f0e09080b0a
  .quad 0x0504070601000302
  .quad 0x0d0c0f0e09080b0a
9:
" %}
      {% if is_absorbing %}
        asm({{ template }} :: "r"({{ state }}), "r"({{ group_count }})
          : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "r10", "r11", "r12", "r13", "r14", "r15",
            "ymm0", "ymm1", "ymm2", "ymm3", "ymm4", "ymm5", "ymm6", "ymm7", "ymm8", "ymm9",
            "ymm10", "ymm11", "ymm12", "ymm13", "ymm14", "ymm15", "memory", "flags")
      {% else %}
        {% if shift > 0 %}
          {% template = "  mov $5, %r12\n" + template %}
        {% end %}
        asm({{ template }} :: "r"({{ state }}), "r"({{ scratch }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }}), "r"({{ key_block || 0_u64 }})
          : "rcx", "rdx", "r8", "r9", "r10", "r11", "r12",
            "ymm0", "ymm1", "ymm2", "ymm3", "ymm4", "ymm5", "ymm6", "ymm7", "ymm8", "ymm9",
            "ymm10", "ymm11", "ymm12", "ymm13", "ymm14", "ymm15", "memory", "flags")
      {% end %}
    end

    # One Poly1305 block on the general registers, h = (h + m + 2^128) * r
    # partly reduced, for `xor_chacha20_keystream_absorbing_poly1305`: the
    # arrangement of OpenSSL's `poly1305_iteration`, with r's two words and
    # s1 = r1 + r1 / 4 read from the parameter block at $0. `@M` and `@N`
    # stand for the addresses of the block's two words. Registers: r13 to r15 the accumulator, rbx, rsi
    # and rdi the product's words, rax and rdx the multiplies'.
    POLY1305_BLOCK_LINES = "  add @M, %r13
  adc @N, %r14
  adc $$1, %r15
  mov 352($0), %rax
  mulq %r13
  mov %rax, %rsi
  mov 344($0), %rax
  mov %rdx, %rdi
  mulq %r13
  mov %rax, %r13
  mov 344($0), %rax
  mov %rdx, %rbx
  mulq %r14
  add %rax, %rsi
  mov 360($0), %rax
  adc %rdx, %rdi
  mulq %r14
  mov %r15, %r14
  add %rax, %r13
  adc %rdx, %rbx
  imulq 360($0), %r14
  add %r14, %rsi
  mov %rbx, %r14
  adc $$0, %rdi
  imulq 344($0), %r15
  add %rsi, %r14
  mov $$-4, %rax
  adc %r15, %rdi
  and %rdi, %rax
  mov %rdi, %r15
  shrq $$2, %rdi
  and $$3, %r15
  add %rdi, %rax
  add %rax, %r13
  adc $$0, %r14
  adc $$0, %r15
"

    # ChaCha20 that also absorbs into Poly1305, the pass that processors
    # whose vector units and general units work side by side (Zen 3) run
    # fastest: each pass of `xor_chacha20_keystream_on_256_bit_registers`
    # (512 bytes) carries as many bytes of Poly1305 blocks
    # (`POLY1305_BLOCK_LINES`) on the general registers, spread through its
    # rounds. *is_sealing* true absorbs ciphertext already written, the 512
    # bytes that end 64 bytes into what the pass writes (the last four
    # blocks wait for its stores), since the first group carries 448
    # message bytes; false absorbs the bytes the pass reads.
    #
    # *parameters* is a block of 384 bytes, wiped by the caller: 256 bytes
    # of scratch, the sixteen words of the ChaCha20 state (from 256; word
    # 12, the counter, is left at the block after the last), the Poly1305
    # accumulator's three words (320, read and written), r's two words and
    # s1 (344), and the input and output addresses (368 and 376).
    # *group_count* (at least 1) passes run.
    macro xor_chacha20_keystream_absorbing_poly1305(parameters, group_count, is_sealing)
      ::Amber::Beryl::Crypto::X8664CipherInstructions.xor_chacha20_keystream_on_256_bit_registers({{ parameters }}, nil, nil, nil, {{ group_count }},
        absorbing: {{ is_sealing ? "seal" : "open" }})
    end

    # ChaCha20 on AVX-512 that shares Poly1305 between the general
    # registers and the vector code: each 1024-byte pass of
    # `xor_chacha20_keystream_on_512_bit_registers` absorbs
    # *absorbed_block_count* blocks (at most 64) of a stretch of message
    # that starts at the address at 384 of *parameters*, on the general
    # registers, spread through its rounds; the vector code (IFMA) absorbs
    # the rest of the message after it. Sealing, the stretch is ciphertext
    # the passes before wrote, since it starts at the message and moves on
    # by less than a pass. The parameter block is that of
    # `xor_chacha20_keystream_absorbing_poly1305`, 392 bytes, its scratch
    # unused; the address at 384 is left after the blocks absorbed.
    macro xor_chacha20_keystream_sharing_poly1305(parameters, group_count, absorbed_block_count)
      ::Amber::Beryl::Crypto::X8664CipherInstructions.xor_chacha20_keystream_on_512_bit_registers({{ parameters }}, nil, nil, {{ group_count }},
        absorbed_block_count: {{ absorbed_block_count }})
    end

    # One pass of `xor_chacha20_keystream` (three blocks) from the
    # parameter block of `xor_chacha20_keystream_absorbing_poly1305`, that
    # absorbs *block_count* Poly1305 blocks at *absorbed* on the general
    # registers meanwhile: the last pass of a seal on AVX2, whose pending
    # ciphertext (448 bytes) would otherwise be absorbed after it. The input
    # and output are the parameter block's, the counter its word 12; neither
    # the counter nor the pointers move. The statement leaves two general
    # registers to the compiler for its operands.
    macro xor_chacha20_keystream_absorbing_poly1305_on_128_bit_registers(parameters, absorbed, block_count)
      {% template = "  mov 368($0), %r10\n  mov 376($0), %r11\n  mov 304($0), %r12d\n  mov 320($0), %r13\n  mov 328($0), %r14\n  mov 336($0), %r15
  lea 8f(%rip), %r8
  movdqu (%r8), %xmm14
  movdqu 16(%r8), %xmm15
" %}
      {% for block in 0...3 %}
        {% for row in 0...4 %}
          {% template = template + "  movdqu #{256 + row * 16}($0), %xmm#{block * 4 + row}\n" %}
        {% end %}
        {% template = template + "  lea #{block}(%r12), %r8d\n  pinsrd $$0, %r8d, %xmm#{block * 4 + 3}\n" %}
      {% end %}
      {% rounds = "" %}
      {% for double_round in 0...10 %}
        {% for half in 0...2 %}
          {% for step in [[0, 1, 3, 16], [2, 3, 1, 12], [0, 1, 3, 8], [2, 3, 1, 7]] %}
            {% for block in 0...3 %}
              {% rounds = rounds + "  paddd %xmm#{block * 4 + step[1]}, %xmm#{block * 4 + step[0]}\n" %}
            {% end %}
            {% for block in 0...3 %}
              {% rounds = rounds + "  pxor %xmm#{block * 4 + step[0]}, %xmm#{block * 4 + step[2]}\n" %}
            {% end %}
            {% for block in 0...3 %}
              {% target = "%xmm#{block * 4 + step[2]}" %}
              {% if step[3] == 16 %}
                {% rounds = rounds + "  pshufb %xmm14, #{target.id}\n" %}
              {% elsif step[3] == 8 %}
                {% rounds = rounds + "  pshufb %xmm15, #{target.id}\n" %}
              {% else %}
                {% scratch = "%xmm#{12 + block % 2}" %}
                {% rounds = rounds + "  movdqa #{target.id}, #{scratch.id}\n  pslld $$#{step[3]}, #{target.id}\n  psrld $$#{32 - step[3]}, #{scratch.id}\n  por #{scratch.id}, #{target.id}\n" %}
              {% end %}
            {% end %}
          {% end %}
          {% for block in 0...3 %}
            {% if half == 0 %}
              {% rounds = rounds + "  pshufd $$0x39, %xmm#{block * 4 + 1}, %xmm#{block * 4 + 1}\n  pshufd $$0x4e, %xmm#{block * 4 + 2}, %xmm#{block * 4 + 2}\n  pshufd $$0x93, %xmm#{block * 4 + 3}, %xmm#{block * 4 + 3}\n" %}
            {% else %}
              {% rounds = rounds + "  pshufd $$0x93, %xmm#{block * 4 + 1}, %xmm#{block * 4 + 1}\n  pshufd $$0x4e, %xmm#{block * 4 + 2}, %xmm#{block * 4 + 2}\n  pshufd $$0x39, %xmm#{block * 4 + 3}, %xmm#{block * 4 + 3}\n" %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
      {% list_of_round_lines = rounds.split("\n").reject { |line| line.empty? } %}
      {% list_of_poly1305_lines = [] of String %}
      {% for block in 0...block_count %}
        {% lines = ::Amber::Beryl::Crypto::X8664CipherInstructions::POLY1305_BLOCK_LINES.gsub(/@M/, "#{block * 16}($1)").gsub(/@N/, "#{block * 16 + 8}($1)") %}
        {% list_of_poly1305_lines = list_of_poly1305_lines + lines.split("\n").reject { |line| line.empty? } %}
      {% end %}
      {% emitted = 0 %}
      {% for line, index in list_of_round_lines %}
        {% template = template + line + "\n" %}
        {% target = ((index + 1) * list_of_poly1305_lines.size) // list_of_round_lines.size %}
        {% if target > emitted %}
          {% for poly1305_line in list_of_poly1305_lines[emitted...target] %}
            {% template = template + poly1305_line + "\n" %}
          {% end %}
          {% emitted = target %}
        {% end %}
      {% end %}
      {% for block in 0...3 %}
        {% for row in 0...4 %}
          {% template = template + "  movdqu #{256 + row * 16}($0), %xmm12\n" %}
          {% if row == 3 %}
            {% template = template + "  lea #{block}(%r12), %r8d\n  pinsrd $$0, %r8d, %xmm12\n" %}
          {% end %}
          {% template = template + "  paddd %xmm12, %xmm#{block * 4 + row}
  movdqu #{block * 64 + row * 16}(%r10), %xmm13
  pxor %xmm13, %xmm#{block * 4 + row}
  movdqu %xmm#{block * 4 + row}, #{block * 64 + row * 16}(%r11)
" %}
        {% end %}
      {% end %}
      {% template = template + "  mov %r13, 320($0)\n  mov %r14, 328($0)\n  mov %r15, 336($0)
  jmp 9f
  .p2align 4
8:
  .quad 0x0504070601000302
  .quad 0x0d0c0f0e09080b0a
  .quad 0x0605040702010003
  .quad 0x0e0d0c0f0a09080b
9:
" %}
      asm({{ template }} :: "r"({{ parameters }}), "r"({{ absorbed }})
        : "rax", "rbx", "rdx", "rsi", "rdi", "r8", "r10", "r11", "r12", "r13", "r14", "r15",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9",
          "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15", "memory", "flags")
    end

    # Blocks of ChaCha20 keystream one pass of
    # `xor_chacha20_keystream_on_512_bit_registers` produces.
    CHACHA20_BLOCKS_PER_512_BIT_GROUP = 16

    # ChaCha20 on AVX-512 (F), sixteen blocks a pass, with the parameters and
    # meaning of `xor_chacha20_keystream_on_256_bit_registers`. The layout
    # of that pass on sixteen lanes (OpenSSL's `ChaCha20_16x`): the 32
    # registers hold every word and leave sixteen spare, and `vprold`
    # rotates in one instruction, so the four quarter rounds of a half round
    # run side by side. The transposition ends with `vshufi32x4`, which
    # gathers the four 128-bit quarters of each block.
    #
    # Registers: r8 the state, r10 input, r11 output, rcx groups left, edx
    # the counter, r12 the key block; zmm0 to zmm15 the words, zmm16 to
    # zmm27 scratch, xmm28 to xmm31 the seventeenth block of a first group.
    # With *key_block* the pass carries that block, so it XORs 1024 bytes
    # after the key block, and *group_count* must be 1.
    #
    # With *absorbed_block_count* it is the 1024-byte pass of
    # `xor_chacha20_keystream_sharing_poly1305`.
    macro xor_chacha20_keystream_on_512_bit_registers(state, input, output, group_count, key_block = nil, absorbed_block_count = nil)
      {% shift = key_block.is_a?(NilLiteral) ? 0 : 64 %}
      {% is_absorbing = !absorbed_block_count.is_a?(NilLiteral) %}
      {% if is_absorbing %}
        {% word_operands = (0...16).map { |word| "#{256 + word * 4}($0)" } %}
        {% counter = "304($0)" %}
        {% template = "  mov $1, %rcx\n  mov 368($0), %r10\n  mov 376($0), %r11\n  mov 384($0), %r12\n  mov 320($0), %r13\n  mov 328($0), %r14\n  mov 336($0), %r15\n1:\n" %}
      {% else %}
        {% word_operands = (0...16).map { |word| "#{word * 4}(%r8)" } %}
        {% counter = "%edx" %}
        {% template = "  mov $0, %r8\n  mov $1, %r10\n  mov $2, %r11\n  mov $3, %rcx\n  mov 48(%r8), %edx\n1:\n" %}
      {% end %}
      {% for word in 0...16 %}
        {% if word == 12 %}
          {% template = template + "  vpbroadcastd #{counter.id}, %zmm12\n  vpaddd 8f(%rip), %zmm12, %zmm12\n" %}
        {% else %}
          {% template = template + "  vpbroadcastd #{word_operands[word].id}, %zmm#{word}\n" %}
        {% end %}
      {% end %}
      {% double_round = "" %}
      {% for quarters in [[[0, 4, 8, 12], [1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15]], [[0, 5, 10, 15], [1, 6, 11, 12], [2, 7, 8, 13], [3, 4, 9, 14]]] %}
        {% for step in [[0, 1, 3, 16], [2, 3, 1, 12], [0, 1, 3, 8], [2, 3, 1, 7]] %}
          {% for quarter in quarters %}
            {% double_round = double_round + "  vpaddd %zmm#{quarter[step[1]]}, %zmm#{quarter[step[0]]}, %zmm#{quarter[step[0]]}\n" %}
          {% end %}
          {% for quarter in quarters %}
            {% double_round = double_round + "  vpxord %zmm#{quarter[step[0]]}, %zmm#{quarter[step[2]]}, %zmm#{quarter[step[2]]}\n" %}
          {% end %}
          {% for quarter in quarters %}
            {% double_round = double_round + "  vprold $$#{step[3]}, %zmm#{quarter[step[2]]}, %zmm#{quarter[step[2]]}\n" %}
          {% end %}
        {% end %}
      {% end %}
      # A first group (with *key_block*) carries a seventeenth block, the one
      # that would otherwise need a pass of its own: its four rows in xmm28
      # to xmm31, a quarter round on all four columns at once as in
      # `xor_chacha20_keystream`, its lines spread through each double round.
      {% if shift > 0 %}
        {% extra_lines = [] of String %}
        {% for half in 0...2 %}
          {% for step in [[28, 29, 31, 16], [30, 31, 29, 12], [28, 29, 31, 8], [30, 31, 29, 7]] %}
            {% extra_lines = extra_lines + ["  vpaddd %xmm#{step[1]}, %xmm#{step[0]}, %xmm#{step[0]}", "  vpxord %xmm#{step[0]}, %xmm#{step[2]}, %xmm#{step[2]}", "  vprold $$#{step[3]}, %xmm#{step[2]}, %xmm#{step[2]}"] %}
          {% end %}
          {% if half == 0 %}
            {% extra_lines = extra_lines + ["  vpshufd $$0x39, %xmm29, %xmm29", "  vpshufd $$0x4e, %xmm30, %xmm30", "  vpshufd $$0x93, %xmm31, %xmm31"] %}
          {% else %}
            {% extra_lines = extra_lines + ["  vpshufd $$0x93, %xmm29, %xmm29", "  vpshufd $$0x4e, %xmm30, %xmm30", "  vpshufd $$0x39, %xmm31, %xmm31"] %}
          {% end %}
        {% end %}
        {% round_lines = double_round.split("\n").reject { |line| line.empty? } %}
        {% merged = "" %}
        {% emitted = 0 %}
        {% for line, index in round_lines %}
          {% merged = merged + line + "\n" %}
          {% target = ((index + 1) * extra_lines.size) // round_lines.size %}
          {% if target > emitted %}
            {% for extra_line in extra_lines[emitted...target] %}
              {% merged = merged + extra_line + "\n" %}
            {% end %}
            {% emitted = target %}
          {% end %}
        {% end %}
        {% double_round = merged %}
        {% template = template + "  vmovdqu32 (%r8), %xmm28\n  vmovdqu32 16(%r8), %xmm29\n  vmovdqu32 32(%r8), %xmm30\n  vmovdqu32 48(%r8), %xmm31\n  lea 16(%rdx), %eax\n  vpinsrd $$0, %eax, %xmm31, %xmm31\n" %}
      {% end %}
      {% rounds = "" %}
      {% for index in 0...10 %}
        {% rounds = rounds + double_round %}
      {% end %}
      # Absorbing, the Poly1305 blocks (from r12, which moves on by as many)
      # are spread through the rounds.
      {% if is_absorbing %}
        {% list_of_round_lines = rounds.split("\n").reject { |line| line.empty? } %}
        {% list_of_poly1305_lines = [] of String %}
        {% for block in 0...absorbed_block_count %}
          {% low_word = "#{block * 16}(%r12)" %}
          {% high_word = "#{block * 16 + 8}(%r12)" %}
          {% lines = ::Amber::Beryl::Crypto::X8664CipherInstructions::POLY1305_BLOCK_LINES.gsub(/@M/, low_word).gsub(/@N/, high_word) %}
          {% list_of_poly1305_lines = list_of_poly1305_lines + lines.split("\n").reject { |line| line.empty? } %}
        {% end %}
        {% rounds = "" %}
        {% emitted = 0 %}
        {% for line, index in list_of_round_lines %}
          {% rounds = rounds + line + "\n" %}
          {% target = ((index + 1) * list_of_poly1305_lines.size) // list_of_round_lines.size %}
          {% if target > emitted %}
            {% for poly1305_line in list_of_poly1305_lines[emitted...target] %}
              {% rounds = rounds + poly1305_line + "\n" %}
            {% end %}
            {% emitted = target %}
          {% end %}
        {% end %}
      {% end %}
      {% template = template + rounds %}
      {% if shift > 0 %}
        {% for row in 0...4 %}
          {% template = template + "  vmovdqu32 #{row * 16}(%r8), %xmm16\n" %}
          {% if row == 3 %}
            {% template = template + "  vpinsrd $$0, %eax, %xmm16, %xmm16\n" %}
          {% end %}
          {% template = template + "  vpaddd %xmm16, %xmm#{28 + row}, %xmm#{28 + row}\n  vpxord #{960 + row * 16}(%r10), %xmm#{28 + row}, %xmm#{28 + row}\n  vmovdqu32 %xmm#{28 + row}, #{960 + row * 16}(%r11)\n" %}
        {% end %}
      {% end %}
      {% for word in 0...16 %}
        {% if word == 12 %}
          {% template = template + "  vpbroadcastd #{counter.id}, %zmm16\n  vpaddd 8f(%rip), %zmm16, %zmm16\n" %}
        {% else %}
          {% template = template + "  vpbroadcastd #{word_operands[word].id}, %zmm16\n" %}
        {% end %}
        {% template = template + "  vpaddd %zmm16, %zmm#{word}, %zmm#{word}\n" %}
      {% end %}
      # Each four words transpose into four registers whose quarter q holds
      # block 4q + k (k = 0 to 3); then the quarters of each block are
      # gathered from the four sets.
      {% list_of_sets = [] of Array(String) %}
      {% for quad in 0...4 %}
        {% a = "%zmm#{quad * 4}" %}
        {% b = "%zmm#{quad * 4 + 1}" %}
        {% c = "%zmm#{quad * 4 + 2}" %}
        {% d = "%zmm#{quad * 4 + 3}" %}
        {% t = "%zmm#{16 + quad}" %}
        {% template = template + "  vpunpckldq #{b.id}, #{a.id}, #{t.id}
  vpunpckhdq #{b.id}, #{a.id}, #{b.id}
  vpunpckldq #{d.id}, #{c.id}, #{a.id}
  vpunpckhdq #{d.id}, #{c.id}, #{d.id}
  vpunpcklqdq #{a.id}, #{t.id}, #{c.id}
  vpunpckhqdq #{a.id}, #{t.id}, #{t.id}
  vpunpcklqdq #{d.id}, #{b.id}, #{a.id}
  vpunpckhqdq #{d.id}, #{b.id}, #{b.id}
" %}
        {% list_of_sets = list_of_sets + [[c, t, a, b]] %}
      {% end %}
      {% for block in 0...4 %}
        {% u0 = list_of_sets[0][block] %}
        {% u1 = list_of_sets[1][block] %}
        {% u2 = list_of_sets[2][block] %}
        {% u3 = list_of_sets[3][block] %}
        {% template = template + "  vshufi32x4 $$0x44, #{u1.id}, #{u0.id}, %zmm20
  vshufi32x4 $$0xee, #{u1.id}, #{u0.id}, %zmm21
  vshufi32x4 $$0x44, #{u3.id}, #{u2.id}, %zmm22
  vshufi32x4 $$0xee, #{u3.id}, #{u2.id}, %zmm23
  vshufi32x4 $$0x88, %zmm22, %zmm20, %zmm24
  vshufi32x4 $$0xdd, %zmm22, %zmm20, %zmm25
  vshufi32x4 $$0x88, %zmm23, %zmm21, %zmm26
  vshufi32x4 $$0xdd, %zmm23, %zmm21, %zmm27
" %}
        {% for quarter in 0...4 %}
          {% offset = (block + 4 * quarter) * 64 - shift %}
          {% if offset < 0 %}
            {% template = template + "  vmovdqu32 %zmm#{24 + quarter}, (%r12)\n" %}
          {% else %}
            {% template = template + "  vpxord #{offset}(%r10), %zmm#{24 + quarter}, %zmm#{24 + quarter}\n  vmovdqu32 %zmm#{24 + quarter}, #{offset}(%r11)\n" %}
          {% end %}
        {% end %}
      {% end %}
      {% if is_absorbing %}
        {% template = template + "  addl $$16, 304($0)\n  add $$#{absorbed_block_count * 16}, %r12\n" %}
      {% else %}
        {% template = template + "  add $$#{shift > 0 ? 17 : 16}, %edx\n" %}
      {% end %}
      {% template = template + "  add $$1024, %r10\n  add $$1024, %r11\n  dec %rcx\n  jnz 1b\n" %}
      {% if is_absorbing %}
        {% template = template + "  mov %r12, 384($0)\n  mov %r13, 320($0)\n  mov %r14, 328($0)\n  mov %r15, 336($0)\n" %}
      {% else %}
        {% template = template + "  mov %edx, 48(%r8)\n" %}
      {% end %}
      {% template = template + "  vzeroupper
  jmp 9f
  .p2align 6
8:
  .long 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
9:
" %}
      {% if is_absorbing %}
        asm({{ template }} :: "r"({{ state }}), "r"({{ group_count }})
          : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "r10", "r11", "r12", "r13", "r14", "r15",
            "zmm0", "zmm1", "zmm2", "zmm3", "zmm4", "zmm5", "zmm6", "zmm7", "zmm8", "zmm9",
            "zmm10", "zmm11", "zmm12", "zmm13", "zmm14", "zmm15", "zmm16", "zmm17", "zmm18", "zmm19",
            "zmm20", "zmm21", "zmm22", "zmm23", "zmm24", "zmm25", "zmm26", "zmm27", "memory", "flags")
      {% else %}
        {% if shift > 0 %}
          {% template = "  mov $4, %r12\n" + template %}
        {% end %}
        asm({{ template }} :: "r"({{ state }}), "r"({{ input }}), "r"({{ output }}), "r"({{ group_count }}), "r"({{ key_block || 0_u64 }})
          : "rax", "rcx", "rdx", "r8", "r10", "r11", "r12",
            "zmm0", "zmm1", "zmm2", "zmm3", "zmm4", "zmm5", "zmm6", "zmm7", "zmm8", "zmm9",
            "zmm10", "zmm11", "zmm12", "zmm13", "zmm14", "zmm15", "zmm16", "zmm17", "zmm18", "zmm19",
            "zmm20", "zmm21", "zmm22", "zmm23", "zmm24", "zmm25", "zmm26", "zmm27", "zmm28", "zmm29", "zmm30", "zmm31", "memory", "flags")
      {% end %}
    end

    # Poly1305 (RFC 8439 §2.5) on AVX2: absorbs *earlier_group_count* (at
    # least 1) groups and then one more, each of four whole 16-byte blocks at
    # *input*, each with its
    # bit 128 set, into the accumulator the table at *table* starts from, and
    # writes the result there. The arrangement of OpenSSL's
    # `poly1305_blocks_avx2` (Goll and Gueron, "Vectorization of Poly1305
    # Message Authentication Code", ITNG 2015): numbers are five limbs of 26
    # bits, one 64-bit lane each, so that `vpmuludq` (32 by 32 bits to 64)
    # multiplies limbs and a product of five limbs sums in 64 bits. Lane j
    # takes blocks j, j + 4, j + 8 and so on and is multiplied by r^4 after
    # each, except after its last block, where lane j is multiplied by
    # r^(4 - j); the lanes then add up to the accumulator of
    # the plain one-block-at-a-time method. The reduction modulo 2^130 - 5
    # folds the limbs above the fifth back multiplied by 5 (the powers come
    # with their limbs times 5) and carries lazily, so limbs stay a little
    # above 26 bits.
    #
    # Loading a group, `vpunpck*qdq` puts the low and high halves of the
    # blocks into lanes in the order 0, 2, 1, 3; the table's last powers
    # follow that order.
    #
    # The table, in vectors of 32 bytes: the accumulator's five limbs in
    # lane 0 (vectors 0 to 4, other lanes zero); r^4's limbs in
    # every lane (5 to 9) and limbs 1 to 4 times 5 (10 to 13); the last
    # powers' limbs (14 to 18) and limbs 1 to 4 times 5 (19 to 22). The
    # statement writes the sums of the lanes' five limbs, in 64-bit words, at
    # vector 23.
    #
    # Registers: r8 the table, r10 input, rcx groups left; ymm0 to ymm4 the
    # accumulators, ymm5 to ymm9 the products, ymm10 a partial product or a
    # carry, ymm11 to ymm14 the message, ymm15 the mask of 26 bits.
    macro absorb_poly1305_groups(table, input, earlier_group_count)
      {% width = 32 %}
      {% v = (0...16).map { |index| "%ymm#{index}" } %}
      {% template = "  mov $0, %r8\n  mov $1, %r10\n  mov $2, %rcx\n  lea 8f(%rip), %rax\n  vpbroadcastq (%rax), #{v[15].id}\n" %}
      {% for limb in 0...5 %}
        {% template = template + "  vmovdqu #{limb * width}(%r8), #{v[limb].id}\n" %}
      {% end %}
      {% lines_by_pass = [] of String %}
      {% for table_base in [5, 14] %}
        {% lines = "  vmovdqu (%r10), #{v[11].id}
  vmovdqu #{width}(%r10), #{v[12].id}
  vpunpcklqdq #{v[12].id}, #{v[11].id}, #{v[13].id}
  vpunpckhqdq #{v[12].id}, #{v[11].id}, #{v[14].id}
  vpand #{v[15].id}, #{v[13].id}, #{v[11].id}
  vpaddq #{v[11].id}, #{v[0].id}, #{v[0].id}
  vpsrlq $$26, #{v[13].id}, #{v[11].id}
  vpand #{v[15].id}, #{v[11].id}, #{v[11].id}
  vpaddq #{v[11].id}, #{v[1].id}, #{v[1].id}
  vpsrlq $$52, #{v[13].id}, #{v[11].id}
  vpsllq $$12, #{v[14].id}, #{v[12].id}
  vpor #{v[12].id}, #{v[11].id}, #{v[11].id}
  vpand #{v[15].id}, #{v[11].id}, #{v[11].id}
  vpaddq #{v[11].id}, #{v[2].id}, #{v[2].id}
  vpsrlq $$14, #{v[14].id}, #{v[11].id}
  vpand #{v[15].id}, #{v[11].id}, #{v[11].id}
  vpaddq #{v[11].id}, #{v[3].id}, #{v[3].id}
  vpsrlq $$40, #{v[14].id}, #{v[11].id}
  vpbroadcastq 8(%rax), #{v[12].id}
  vpor #{v[12].id}, #{v[11].id}, #{v[11].id}
  vpaddq #{v[11].id}, #{v[4].id}, #{v[4].id}
" %}
        # Product limb k sums accumulator limb i times power limb k - i,
        # or times 5 * power limb k - i + 5 when k < i.
        {% for product in 0...5 %}
          {% for limb in 0...5 %}
            {% power = product - limb %}
            {% offset = power >= 0 ? (table_base + power) * width : (table_base + 4 + power + 5) * width %}
            {% if limb == 0 %}
              {% lines = lines + "  vpmuludq #{offset}(%r8), #{v[limb].id}, #{v[5 + product].id}\n" %}
            {% else %}
              {% lines = lines + "  vpmuludq #{offset}(%r8), #{v[limb].id}, #{v[10].id}\n  vpaddq #{v[10].id}, #{v[5 + product].id}, #{v[5 + product].id}\n" %}
            {% end %}
          {% end %}
        {% end %}
        {% for carry in [[3, 4], [0, 1], [4, 0], [1, 2], [2, 3], [0, 1], [3, 4]] %}
          {% lines = lines + "  vpsrlq $$26, #{v[5 + carry[0]].id}, #{v[10].id}\n  vpand #{v[15].id}, #{v[5 + carry[0]].id}, #{v[5 + carry[0]].id}\n  vpaddq #{v[10].id}, #{v[5 + carry[1]].id}, #{v[5 + carry[1]].id}\n" %}
          {% if carry[0] == 4 %}
            {% lines = lines + "  vpsllq $$2, #{v[10].id}, #{v[10].id}\n  vpaddq #{v[10].id}, #{v[5].id}, #{v[5].id}\n" %}
          {% end %}
        {% end %}
        {% lines_by_pass = lines_by_pass + [lines] %}
      {% end %}
      {% template = template + "1:\n" + lines_by_pass[0] %}
      {% for limb in 0...5 %}
        {% template = template + "  vmovdqa #{v[5 + limb].id}, #{v[limb].id}\n" %}
      {% end %}
      {% template = template + "  add $$#{width * 2}, %r10\n  dec %rcx\n  jnz 1b\n" + lines_by_pass[1] %}
      # The lanes of each product limb add up into lane 0.
      {% for limb in 0...5 %}
        {% product = 5 + limb %}
        {% template = template + "  vextracti128 $$1, %ymm#{product}, %xmm10\n  vpaddq %xmm10, %xmm#{product}, %xmm#{product}\n  vpsrldq $$8, %xmm#{product}, %xmm10\n  vpaddq %xmm10, %xmm#{product}, %xmm#{product}\n  vmovq %xmm#{product}, #{23 * width + limb * 8}(%r8)\n" %}
      {% end %}
      {% template = template + "  vzeroupper
  jmp 9f
  .p2align 3
8:
  .quad 0x3ffffff
  .quad 0x1000000
9:
" %}
      asm({{ template }} :: "r"({{ table }}), "r"({{ input }}), "r"({{ earlier_group_count }})
        : "rax", "rcx", "r8", "r10",
          "ymm0", "ymm1", "ymm2", "ymm3", "ymm4", "ymm5", "ymm6", "ymm7", "ymm8", "ymm9",
          "ymm10", "ymm11", "ymm12", "ymm13", "ymm14", "ymm15", "memory", "flags")
    end

    # Poly1305 on AVX-512 IFMA (`vpmadd52luq` and `vpmadd52huq`, which add
    # the low or high 52 bits of the 104-bit product of two 52-bit numbers
    # to a 64-bit lane), in the arrangement of OpenSSL's
    # `poly1305_blocks_vpmadd52`: numbers are three limbs of 44, 44 and 42
    # bits. A product limb sums three products; their high halves count
    # 2^52 more, so they join the next limb shifted left by 8, and those of
    # the top limb fold back to the bottom as 2^140 = 5 * 2^10 modulo
    # 2^130 - 5. Products at 2^132 and up use the power's limbs times 20
    # (2^132 = 20 modulo 2^130 - 5).
    #
    # *set_count* (1 or 2) sets of eight lanes run side by side, so that
    # each set's chain of multiplies and carries overlaps the other's: a
    # group is 8 * *set_count* blocks, set s taking blocks 8s to 8s + 7 of
    # it, in the lane order of `absorb_poly1305_groups` (0, 4, 1, 5, 2, 6, 3,
    # 7, from `vpunpck*qdq` on 128-bit lanes). The statement absorbs
    # *earlier_group_count* (at least 1) groups and then one more, at
    # *input*: every lane is multiplied by r^n (n the lanes in all) after
    # each block but its last, and after its last by the power the table
    # gives it.
    #
    # The table, in vectors of 64 bytes: the accumulator's limbs in lane 0
    # (vectors 0 to 2); r^n's limbs in every lane, then limbs 1 and 2 times
    # 20 (3 to 7); each set's last powers likewise (8 to 12, then 13 to 17).
    # The statement writes the sums of all lanes' three limbs after them.
    #
    # With *scalar_block_count*, the statement also absorbs that many
    # blocks a pass on the general registers (`POLY1305_BLOCK_LINES`), a
    # stretch of its own after the vectors' blocks, from an accumulator of
    # its own; the caller joins the two. The table then holds, from word
    # 152, r's two words and s1, that accumulator (read and written), the
    # stretch's address and the input's address, and the statement takes
    # the table and *earlier_group_count* alone (*input* unused): it uses
    # every general register but two.
    #
    # Registers: r8 the table, r10 input, rcx groups left; zmm14 and zmm15
    # the masks of 44 and 42 bits, zmm30 bit 40; r^n's five vectors in
    # zmm25 to zmm28 and zmm31, so the multiplies of the loop read no
    # memory; the message in zmm9 to zmm12, which the sets take in turn;
    # for set s, from zmm(16s): the accumulators (3), the low (3) and high
    # (3) halves of the products and, at 13, a carry.
    macro absorb_poly1305_groups_with_fused_multiply_add(table, input, earlier_group_count, set_count, scalar_block_count = 0)
      {% if scalar_block_count > 0 %}
        {% template = "  mov $0, %r8\n  mov $1, %rcx\n  mov 1272(%r8), %r10\n  mov 1264(%r8), %r9\n  mov 1240(%r8), %r13\n  mov 1248(%r8), %r14\n  mov 1256(%r8), %r15\n" %}
      {% else %}
        {% template = "  mov $0, %r8\n  mov $1, %r10\n  mov $2, %rcx\n" %}
      {% end %}
      {% template = template + "  lea 8f(%rip), %rax
  vpbroadcastq (%rax), %zmm14
  vpbroadcastq 8(%rax), %zmm15
  vpbroadcastq 16(%rax), %zmm30
  vmovdqu64 (%r8), %zmm0
  vmovdqu64 64(%r8), %zmm1
  vmovdqu64 128(%r8), %zmm2
  vmovdqu64 192(%r8), %zmm25
  vmovdqu64 256(%r8), %zmm26
  vmovdqu64 320(%r8), %zmm27
  vmovdqu64 384(%r8), %zmm28
  vmovdqu64 448(%r8), %zmm31
" %}
      {% if set_count == 2 %}
        {% template = template + "  vpxorq %zmm16, %zmm16, %zmm16\n  vpxorq %zmm17, %zmm17, %zmm17\n  vpxorq %zmm18, %zmm18, %zmm18\n" %}
      {% end %}
      {% lines_by_pass = [] of String %}
      {% for pass in 0...2 %}
        {% lines = "" %}
        # Each step lists the lines of every set, the sets taking turns.
        {% list_of_steps = [] of Array(String) %}
        {% for set in 0...set_count %}
          {% z = (0...14).map { |index| index >= 9 && index <= 12 ? "%zmm#{index}" : "%zmm#{set * 16 + index}" } %}
          {% power_base = pass == 0 ? 3 : 8 + 5 * set %}
          {% steps = [] of String %}
          {% steps = steps + ["  vmovdqu64 #{set * 128}(%r10), #{z[9].id}\n  vmovdqu64 #{set * 128 + 64}(%r10), #{z[10].id}\n",
                              "  vpunpcklqdq #{z[10].id}, #{z[9].id}, #{z[11].id}\n  vpunpckhqdq #{z[10].id}, #{z[9].id}, #{z[12].id}\n",
                              "  vpandq %zmm14, #{z[11].id}, #{z[9].id}\n  vpsrlq $$44, #{z[11].id}, #{z[11].id}\n",
                              "  vpaddq #{z[9].id}, #{z[0].id}, #{z[0].id}\n  vpsllq $$20, #{z[12].id}, #{z[10].id}\n",
                              "  vporq #{z[10].id}, #{z[11].id}, #{z[11].id}\n  vpsrlq $$24, #{z[12].id}, #{z[12].id}\n",
                              "  vpandq %zmm14, #{z[11].id}, #{z[11].id}\n  vporq %zmm30, #{z[12].id}, #{z[12].id}\n",
                              "  vpaddq #{z[11].id}, #{z[1].id}, #{z[1].id}\n  vpaddq #{z[12].id}, #{z[2].id}, #{z[2].id}\n"] %}
          {% clearing = "" %}
          {% for product in 3...9 %}
            {% clearing = clearing + "  vpxorq #{z[product].id}, #{z[product].id}, #{z[product].id}\n" %}
          {% end %}
          {% steps = steps + [clearing] %}
          # Product limb k takes accumulator limb i times power limb k - i,
          # or times 20 * power limb k - i + 3 when k < i.
          {% for limb in 0...3 %}
            {% for product in 0...3 %}
              {% power = product - limb %}
              {% vector = power >= 0 ? power_base + power : power_base + 2 + power + 3 %}
              {% operand = pass == 0 ? {3 => "%zmm25", 4 => "%zmm26", 5 => "%zmm27", 6 => "%zmm28", 7 => "%zmm31"}[vector] : "#{vector * 64}(%r8)" %}
              {% steps = steps + ["  vpmadd52luq #{operand.id}, #{z[limb].id}, #{z[3 + product].id}\n  vpmadd52huq #{operand.id}, #{z[limb].id}, #{z[6 + product].id}\n"] %}
            {% end %}
          {% end %}
          {% steps = steps + ["  vpsrlq $$44, #{z[3].id}, #{z[13].id}\n  vpsllq $$8, #{z[6].id}, #{z[6].id}\n  vpandq %zmm14, #{z[3].id}, #{z[0].id}\n",
                              "  vpaddq #{z[13].id}, #{z[6].id}, #{z[6].id}\n  vpaddq #{z[6].id}, #{z[4].id}, #{z[4].id}\n",
                              "  vpsrlq $$44, #{z[4].id}, #{z[13].id}\n  vpsllq $$8, #{z[7].id}, #{z[7].id}\n  vpandq %zmm14, #{z[4].id}, #{z[1].id}\n",
                              "  vpaddq #{z[13].id}, #{z[7].id}, #{z[7].id}\n  vpaddq #{z[7].id}, #{z[5].id}, #{z[5].id}\n",
                              "  vpsrlq $$42, #{z[5].id}, #{z[13].id}\n  vpsllq $$10, #{z[8].id}, #{z[8].id}\n  vpandq %zmm15, #{z[5].id}, #{z[2].id}\n",
                              "  vpaddq #{z[13].id}, #{z[8].id}, #{z[8].id}\n  vpaddq #{z[8].id}, #{z[0].id}, #{z[0].id}\n  vpsllq $$2, #{z[8].id}, #{z[8].id}\n",
                              "  vpaddq #{z[8].id}, #{z[0].id}, #{z[0].id}\n",
                              "  vpsrlq $$44, #{z[0].id}, #{z[13].id}\n  vpandq %zmm14, #{z[0].id}, #{z[0].id}\n",
                              "  vpaddq #{z[13].id}, #{z[1].id}, #{z[1].id}\n"] %}
          {% list_of_steps = list_of_steps + [steps] %}
        {% end %}
        # The sets share the message registers, so each set's first seven
        # steps (the message) run before the next set's.
        {% for set in 0...set_count %}
          {% for step in 0...7 %}
            {% lines = lines + list_of_steps[set][step] %}
          {% end %}
        {% end %}
        {% for step in 7...list_of_steps[0].size %}
          {% for set in 0...set_count %}
            {% lines = lines + list_of_steps[set][step] %}
          {% end %}
        {% end %}
        {% lines_by_pass = lines_by_pass + [lines] %}
      {% end %}
      # Mixed, the scalar blocks of each pass are spread through its lines.
      {% loop_lines = lines_by_pass[0] %}
      {% if scalar_block_count > 0 %}
        {% list_of_vector_lines = loop_lines.split("\n").reject { |line| line.empty? } %}
        {% list_of_scalar_lines = [] of String %}
        {% for block in 0...scalar_block_count %}
          {% lines = ::Amber::Beryl::Crypto::X8664CipherInstructions::POLY1305_BLOCK_LINES.gsub(/344\(\$0\)/, "1216(%r8)").gsub(/352\(\$0\)/, "1224(%r8)").gsub(/360\(\$0\)/, "1232(%r8)").gsub(/@M/, "#{block * 16}(%r9)").gsub(/@N/, "#{block * 16 + 8}(%r9)") %}
          {% list_of_scalar_lines = list_of_scalar_lines + lines.split("\n").reject { |line| line.empty? } %}
        {% end %}
        {% loop_lines = "" %}
        {% emitted = 0 %}
        {% for line, index in list_of_vector_lines %}
          {% loop_lines = loop_lines + line + "\n" %}
          {% target = ((index + 1) * list_of_scalar_lines.size) // list_of_vector_lines.size %}
          {% if target > emitted %}
            {% for scalar_line in list_of_scalar_lines[emitted...target] %}
              {% loop_lines = loop_lines + scalar_line + "\n" %}
            {% end %}
            {% emitted = target %}
          {% end %}
        {% end %}
        {% loop_lines = loop_lines + "  add $$#{16 * scalar_block_count}, %r9\n" %}
      {% end %}
      {% template = template + "1:\n" + loop_lines + "  add $$#{128 * set_count}, %r10\n  dec %rcx\n  jnz 1b\n" + lines_by_pass[1] %}
      {% if scalar_block_count > 0 %}
        {% template = template + "  mov %r13, 1240(%r8)\n  mov %r14, 1248(%r8)\n  mov %r15, 1256(%r8)\n" %}
      {% end %}
      {% if set_count == 2 %}
        {% template = template + "  vpaddq %zmm16, %zmm0, %zmm0\n  vpaddq %zmm17, %zmm1, %zmm1\n  vpaddq %zmm18, %zmm2, %zmm2\n" %}
      {% end %}
      {% for limb in 0...3 %}
        {% template = template + "  vextracti64x4 $$1, %zmm#{limb}, %ymm13
  vpaddq %ymm13, %ymm#{limb}, %ymm#{limb}
  vextracti128 $$1, %ymm#{limb}, %xmm13
  vpaddq %xmm13, %xmm#{limb}, %xmm#{limb}
  vpsrldq $$8, %xmm#{limb}, %xmm13
  vpaddq %xmm13, %xmm#{limb}, %xmm#{limb}
  vmovq %xmm#{limb}, #{(8 + 5 * set_count) * 64 + limb * 8}(%r8)
" %}
      {% end %}
      {% template = template + "  vzeroupper
  jmp 9f
  .p2align 3
8:
  .quad 0xfffffffffff
  .quad 0x3ffffffffff
  .quad 0x10000000000
9:
" %}
      {% if scalar_block_count > 0 %}
        asm({{ template }} :: "r"({{ table }}), "r"({{ earlier_group_count }})
          : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r13", "r14", "r15",
            "zmm0", "zmm1", "zmm2", "zmm3", "zmm4", "zmm5", "zmm6", "zmm7", "zmm8", "zmm9", "zmm10",
            "zmm11", "zmm12", "zmm13", "zmm14", "zmm15", "zmm16", "zmm17", "zmm18", "zmm19", "zmm20",
            "zmm21", "zmm22", "zmm23", "zmm24", "zmm25", "zmm26", "zmm27", "zmm28", "zmm29", "zmm30",
            "zmm31", "memory", "flags")
      {% else %}
        asm({{ template }} :: "r"({{ table }}), "r"({{ input }}), "r"({{ earlier_group_count }})
          : "rax", "rcx", "r8", "r10",
            "zmm0", "zmm1", "zmm2", "zmm3", "zmm4", "zmm5", "zmm6", "zmm7", "zmm8", "zmm9", "zmm10",
            "zmm11", "zmm12", "zmm13", "zmm14", "zmm15", "zmm16", "zmm17", "zmm18", "zmm19", "zmm20",
            "zmm21", "zmm22", "zmm23", "zmm24", "zmm25", "zmm26", "zmm27", "zmm28", "zmm29", "zmm30",
            "zmm31", "memory", "flags")
      {% end %}
    end
  end
end
