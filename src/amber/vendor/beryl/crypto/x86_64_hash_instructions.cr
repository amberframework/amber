module Amber::Beryl::Crypto
  # :nodoc:
  #
  # The compression functions of SHA-1 and SHA-256 written with the SHA
  # extensions of x86-64 processors (Intel 64 and IA-32 Architectures
  # Software Developer's Manual, volume 2: `sha1rnds4`, `sha1nexte`,
  # `sha1msg1`, `sha1msg2`, `sha256rnds2`, `sha256msg1`, `sha256msg2`), and
  # that of SHA-512 written with AVX2 (or AVX-512) for the message schedule
  # and BMI1 and BMI2 for the rounds. Each macro expands, inside the hash's
  # `compress`, to one block of assembly that mixes whole blocks at
  # *block_pointer* into the state at *state_pointer*.
  #
  # Crystal has no vector types, so the instructions cannot be reached as
  # LLVM intrinsics; the assembly is written out here instead. Its only
  # branches close loops whose counts are constants or the count of blocks
  # left, and it reads memory only at fixed offsets from registers that
  # step by constants, so its timing does not depend on the message or the
  # state. `scripts/check_secret_flow.rb` checks exactly that.
  # The loop's `dec` and `add` write the flags, so each statement names the
  # x86-64 flags clobber "flags"; LLVM ignores "cc" on x86-64 (see
  # `FieldArithmetic::FieldsInAssembly`).
  #
  # Registers: r8 state, r9 message, r10 blocks left, rax constants.
  module X8664HashInstructions
    # SHA-256 (also SHA-224). xmm1 holds a, b, e, f and xmm2 holds c, d, g, h,
    # the layout `sha256rnds2` works on; each call runs two rounds with the
    # two message-plus-constant words in the low half of xmm0. xmm3 to xmm6
    # hold sixteen message words, renewed four at a time by `sha256msg1` and
    # `sha256msg2`. *round_constants* names the 64 constants of FIPS 180-4
    # §4.2.2.
    macro compress_sha256_blocks(state_pointer, block_pointer, block_count, round_constants)
      {% template = "
  mov $0, %r8
  mov $1, %r9
  mov $2, %r10
  lea 8f(%rip), %rax
  movdqu (%r8), %xmm1
  movdqu 16(%r8), %xmm2
  movdqa 256(%rax), %xmm8
  pshufd $$0xb1, %xmm1, %xmm1
  pshufd $$0x1b, %xmm2, %xmm2
  movdqa %xmm1, %xmm7
  palignr $$8, %xmm2, %xmm1
  pblendw $$0xf0, %xmm7, %xmm2
1:
  movdqa %xmm1, %xmm9
  movdqa %xmm2, %xmm10
  movdqu (%r9), %xmm3
  movdqu 16(%r9), %xmm4
  movdqu 32(%r9), %xmm5
  movdqu 48(%r9), %xmm6
  pshufb %xmm8, %xmm3
  pshufb %xmm8, %xmm4
  pshufb %xmm8, %xmm5
  pshufb %xmm8, %xmm6
" %}
      {% for quad in 0...16 %}
        {% words = 3 + quad % 4 %}
        {% next_words = 3 + (quad + 1) % 4 %}
        {% previous_words = 3 + (quad + 3) % 4 %}
        {% template = template + "  movdqa #{quad * 16}(%rax), %xmm0
  paddd %xmm#{words}, %xmm0
  sha256rnds2 %xmm0, %xmm1, %xmm2
" %}
        {% if quad >= 3 && quad <= 14 %}
          {% template = template + "  movdqa %xmm#{words}, %xmm7
  palignr $$4, %xmm#{previous_words}, %xmm7
  paddd %xmm7, %xmm#{next_words}
  sha256msg2 %xmm#{words}, %xmm#{next_words}
" %}
        {% end %}
        {% template = template + "  pshufd $$0x0e, %xmm0, %xmm0\n  sha256rnds2 %xmm0, %xmm2, %xmm1\n" %}
        {% if quad >= 1 && quad <= 12 %}
          {% template = template + "  sha256msg1 %xmm#{words}, %xmm#{previous_words}\n" %}
        {% end %}
      {% end %}
      {% template = template + "  paddd %xmm9, %xmm1
  paddd %xmm10, %xmm2
  add $$64, %r9
  dec %r10
  jnz 1b
  pshufd $$0x1b, %xmm1, %xmm1
  pshufd $$0xb1, %xmm2, %xmm2
  movdqa %xmm1, %xmm7
  pblendw $$0xf0, %xmm2, %xmm1
  palignr $$8, %xmm7, %xmm2
  movdqu %xmm1, (%r8)
  movdqu %xmm2, 16(%r8)
  jmp 9f
  .p2align 4
8:
" %}
      {% for constant in round_constants.resolve %}
        {% template = template + "  .long #{constant}\n".gsub(/_u32/, "") %}
      {% end %}
      {% template = template + "  .quad 0x0405060700010203\n  .quad 0x0c0d0e0f08090a0b\n9:\n" %}
      asm({{ template }} :: "r"({{ state_pointer }}), "r"({{ block_pointer }}), "r"({{ block_count }}) : "rax", "r8", "r9", "r10", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "memory", "flags")
    end

    # SHA-1. xmm1 holds a, b, c, d; `sha1rnds4` runs four rounds, taking e
    # (prepared by `sha1nexte`) from xmm2 and xmm3 in turn. xmm4 to xmm7 hold
    # sixteen message words, renewed four at a time by `sha1msg1` and
    # `sha1msg2`.
    macro compress_sha1_blocks(state_pointer, block_pointer, block_count)
      {% template = "
  mov $0, %r8
  mov $1, %r9
  mov $2, %r10
  lea 8f(%rip), %rax
  movdqu (%r8), %xmm1
  pxor %xmm2, %xmm2
  pinsrd $$3, 16(%r8), %xmm2
  pshufd $$0x1b, %xmm1, %xmm1
  movdqa (%rax), %xmm8
1:
  movdqa %xmm1, %xmm9
  movdqa %xmm2, %xmm10
  movdqu (%r9), %xmm4
  movdqu 16(%r9), %xmm5
  movdqu 32(%r9), %xmm6
  movdqu 48(%r9), %xmm7
  pshufb %xmm8, %xmm4
  pshufb %xmm8, %xmm5
  pshufb %xmm8, %xmm6
  pshufb %xmm8, %xmm7
" %}
      {% for quad in 0...20 %}
        {% words = 4 + quad % 4 %}
        {% e_now = 2 + quad % 2 %}
        {% e_next = 3 - quad % 2 %}
        {% if quad == 0 %}
          {% template = template + "  paddd %xmm#{words}, %xmm#{e_now}\n" %}
        {% else %}
          {% template = template + "  sha1nexte %xmm#{words}, %xmm#{e_now}\n" %}
        {% end %}
        {% template = template + "  movdqa %xmm1, %xmm#{e_next}\n" %}
        {% if quad >= 3 && quad <= 18 %}
          {% template = template + "  sha1msg2 %xmm#{words}, %xmm#{4 + (quad + 1) % 4}\n" %}
        {% end %}
        {% template = template + "  sha1rnds4 $$#{quad // 5}, %xmm#{e_now}, %xmm1\n" %}
        {% if quad >= 1 && quad <= 16 %}
          {% template = template + "  sha1msg1 %xmm#{words}, %xmm#{4 + (quad + 3) % 4}\n" %}
        {% end %}
        {% if quad >= 2 && quad <= 17 %}
          {% template = template + "  pxor %xmm#{words}, %xmm#{4 + (quad + 2) % 4}\n" %}
        {% end %}
      {% end %}
      {% template = template + "  sha1nexte %xmm10, %xmm2
  paddd %xmm9, %xmm1
  add $$64, %r9
  dec %r10
  jnz 1b
  pshufd $$0x1b, %xmm1, %xmm1
  movdqu %xmm1, (%r8)
  pextrd $$3, %xmm2, 16(%r8)
  jmp 9f
  .p2align 4
8:
  .quad 0x08090a0b0c0d0e0f
  .quad 0x0001020304050607
9:
" %}
      asm({{ template }} :: "r"({{ state_pointer }}), "r"({{ block_pointer }}), "r"({{ block_count }}) : "rax", "r8", "r9", "r10", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "memory", "flags")
    end

    # SHA-512 (also SHA-384 and SHA-512/256), in the layout of OpenSSL's
    # `sha512_block_data_order_avx2` (crypto/sha/asm/sha512-x86_64.pl): the
    # message schedule (FIPS 180-4 §6.4.2 step 1) runs in the 256-bit
    # registers, the low 128-bit lane on the first block and the high lane
    # on the second, so one pass of vector instructions schedules two
    # blocks; the rounds run in the general registers with `rorx` (BMI2)
    # and `andn` (BMI1). While the first block's rounds run, the vector code
    # computes the message words sixteen rounds ahead and stores each pair,
    # with its round constants added, to a table on the stack; the second
    # block's rounds read their words from that table and need no vector
    # work.
    #
    # With *second_block* false the statement mixes the one block at
    # *block_pointer* into the state; with it true, the two blocks there.
    # With *avx512* true the schedule rotates with `vprorq` and combines
    # three terms with `vpternlogq` (AVX512F and AVX512VL, on the same
    # 256-bit registers), 15 vector instructions per pair of words instead
    # of 25.
    #
    # Each round takes Ch(e, f, g) = (e & f) + (~e & g), whose two terms
    # have no bit in common, and Maj(a, b, c) = b ^ ((a ^ b) & (b ^ c)),
    # where b ^ c is the a ^ b of the round before. The eight working
    # variables rename instead of moving, as in the portable code.
    #
    # The statement uses every general register: rdi and rsi bring the
    # state and the message and are put back as they came. Its table lies
    # below the red zone of the function around it, aligned to 64 bytes, and
    # rsp is put back before the statement ends. Its two loops (four passes
    # of sixteen rounds with the schedule, then for the second block ten
    # passes of eight rounds) count down in rbp from constants, and every
    # address is a register plus a constant, so the timing does not depend
    # on the message or the state.
    #
    # Registers: rax, rbx, rcx, rdx, r8, r9, r10, r11 the working variables
    # (a to h in the first round); r12 and r13 for Σ0 and Σ1; r14 and r15
    # in turn for Maj and for the Ch terms; rdi the table position; rsi the
    # round constants (rax until the state is loaded), and in the second
    # block's rounds with AVX-512 the old d; rbp the passes left.
    # ymm0 to ymm7 hold sixteen message words of each block, ymm8 to ymm11
    # are scratch and ymm12 holds the byte order mask.
    macro compress_sha512_blocks(state_pointer, block_pointer, round_constants, second_block, avx512)
      {%
        names = %w(rax rbx rcx rdx r8 r9 r10 r11)
        table_bytesize = 1280
        saved_rsp = "#{table_bytesize}(%rsp)"
        saved_state = "#{table_bytesize + 8}(%rsp)"
        saved_message = "#{table_bytesize + 16}(%rsp)"
        lines = [] of StringLiteral
        lines << "mov %rsp, %rax"
        lines << "sub $$#{table_bytesize + 192}, %rsp"
        lines << "and $$-64, %rsp"
        lines << "mov %rax, #{saved_rsp.id}"
        lines << "mov %rdi, #{saved_state.id}"
        lines << "mov %rsi, #{saved_message.id}"
        lines << "lea 8f(%rip), %rax"
        lines << "vmovdqu #{table_bytesize}(%rax), %ymm12"
      %}
      {% for pair in 0...8 %}
        {% lines << "vmovdqu #{pair * 16}(%rsi), %xmm#{pair}" %}
        {% if second_block %}
          {% lines << "vinserti128 $$1, #{128 + pair * 16}(%rsi), %ymm#{pair}, %ymm#{pair}" %}
        {% end %}
        {% lines << "vpshufb %ymm12, %ymm#{pair}, %ymm#{pair}" %}
        {% lines << "vpaddq #{pair * 32}(%rax), %ymm#{pair}, %ymm8" %}
        {% lines << "vmovdqa %ymm8, #{pair * 32}(%rsp)" %}
      {% end %}
      {% lines << "mov %rax, %rsi" %}
      {% for index in 0...8 %}
        {% lines << "mov #{index * 8}(%rdi), %#{names[index].id}" %}
      {% end %}
      {%
        lines << "mov %rsp, %rdi"
        lines << "mov %rbx, %r14"
        lines << "xor %rcx, %r14"
        lines << "mov $$4, %rbp"
        lines << ".p2align 5"
        lines << "1:"
      %}
      # The first block: 64 rounds in four passes, each scheduling the
      # sixteen words of the pass after it, then the last sixteen rounds.
      {% for part in [:scheduled, :last] %}
        {% for step in 0...8 %}
          {% scalar = [] of StringLiteral %}
          {% for round in [step * 2, step * 2 + 1] %}
            {%
              a = names[(8 - round % 8) % 8]
              b = names[(9 - round % 8) % 8]
              d = names[(11 - round % 8) % 8]
              e = names[(12 - round % 8) % 8]
              f = names[(13 - round % 8) % 8]
              g = names[(14 - round % 8) % 8]
              h = names[(15 - round % 8) % 8]
              maj = round % 2 == 0 ? "r14" : "r15"
              term = round % 2 == 0 ? "r15" : "r14"
              scalar << "add #{(round // 2) * 32 + (round % 2) * 8}(%rdi), %#{h.id}"
              scalar << "mov %#{f.id}, %#{term.id}"
              scalar << "rorx $$41, %#{e.id}, %r12"
              scalar << "rorx $$18, %#{e.id}, %r13"
              scalar << "and %#{e.id}, %#{term.id}"
              scalar << "xor %r13, %r12"
              scalar << "rorx $$14, %#{e.id}, %r13"
              scalar << "add %#{term.id}, %#{h.id}"
              scalar << "andn %#{g.id}, %#{e.id}, %#{term.id}"
              scalar << "xor %r13, %r12"
              scalar << "add %#{term.id}, %#{h.id}"
              scalar << "mov %#{a.id}, %#{term.id}"
              scalar << "add %r12, %#{h.id}"
              scalar << "rorx $$39, %#{a.id}, %r12"
              scalar << "xor %#{b.id}, %#{term.id}"
              scalar << "rorx $$34, %#{a.id}, %r13"
              scalar << "add %#{h.id}, %#{d.id}"
              scalar << "and %#{term.id}, %#{maj.id}"
              scalar << "xor %r13, %r12"
              scalar << "rorx $$28, %#{a.id}, %r13"
              scalar << "xor %#{b.id}, %#{maj.id}"
              scalar << "xor %r13, %r12"
              scalar << "add %#{maj.id}, %#{h.id}"
              scalar << "add %r12, %#{h.id}"
            %}
          {% end %}
          {% vector = [] of StringLiteral %}
          {% if part == :scheduled %}
            {%
              x0 = "%ymm#{step % 8}"
              x1 = "%ymm#{(step + 1) % 8}"
              x4 = "%ymm#{(step + 4) % 8}"
              x5 = "%ymm#{(step + 5) % 8}"
              x7 = "%ymm#{(step + 7) % 8}"
              vector << "vpalignr $$8, #{x0.id}, #{x1.id}, %ymm8"
              vector << "vpalignr $$8, #{x4.id}, #{x5.id}, %ymm9"
            %}
            {% if avx512 %}
              {%
                vector << "vprorq $$1, %ymm8, %ymm10"
                vector << "vpaddq %ymm9, #{x0.id}, #{x0.id}"
                vector << "vprorq $$8, %ymm8, %ymm11"
                vector << "vpsrlq $$7, %ymm8, %ymm8"
                vector << "vpternlogq $$0x96, %ymm11, %ymm10, %ymm8"
                vector << "vprorq $$19, #{x7.id}, %ymm10"
                vector << "vprorq $$61, #{x7.id}, %ymm11"
                vector << "vpsrlq $$6, #{x7.id}, %ymm9"
                vector << "vpaddq %ymm8, #{x0.id}, #{x0.id}"
                vector << "vpternlogq $$0x96, %ymm11, %ymm10, %ymm9"
                vector << "vpaddq %ymm9, #{x0.id}, #{x0.id}"
              %}
            {% else %}
              {%
                vector << "vpsrlq $$1, %ymm8, %ymm10"
                vector << "vpaddq %ymm9, #{x0.id}, #{x0.id}"
                vector << "vpsllq $$63, %ymm8, %ymm11"
                vector << "vpsrlq $$8, %ymm8, %ymm9"
                vector << "vpxor %ymm11, %ymm10, %ymm10"
                vector << "vpsllq $$56, %ymm8, %ymm11"
                vector << "vpxor %ymm9, %ymm10, %ymm10"
                vector << "vpsrlq $$7, %ymm8, %ymm9"
                vector << "vpxor %ymm11, %ymm10, %ymm10"
                vector << "vpsrlq $$6, #{x7.id}, %ymm11"
                vector << "vpxor %ymm9, %ymm10, %ymm10"
                vector << "vpsllq $$3, #{x7.id}, %ymm8"
                vector << "vpaddq %ymm10, #{x0.id}, #{x0.id}"
                vector << "vpxor %ymm8, %ymm11, %ymm11"
                vector << "vpsrlq $$19, #{x7.id}, %ymm9"
                vector << "vpsllq $$45, #{x7.id}, %ymm8"
                vector << "vpxor %ymm9, %ymm11, %ymm11"
                vector << "vpsrlq $$61, #{x7.id}, %ymm9"
                vector << "vpxor %ymm8, %ymm11, %ymm11"
                vector << "vpxor %ymm9, %ymm11, %ymm11"
                vector << "vpaddq %ymm11, #{x0.id}, #{x0.id}"
              %}
            {% end %}
            {%
              vector << "vpaddq #{256 + step * 32}(%rsi), #{x0.id}, %ymm9"
              vector << "vmovdqa %ymm9, #{256 + step * 32}(%rdi)"
            %}
          {% end %}
          # One vector instruction after every two or three scalar ones.
          {% for line, index in scalar %}
            {% lines << line %}
            {% for vector_index in (index * vector.size // scalar.size)...((index + 1) * vector.size // scalar.size) %}
              {% lines << vector[vector_index] %}
            {% end %}
          {% end %}
        {% end %}
        {% if part == :scheduled %}
          {%
            lines << "add $$256, %rdi"
            lines << "add $$256, %rsi"
            lines << "dec %rbp"
            lines << "jnz 1b"
          %}
        {% end %}
      {% end %}
      {%
        lines << "mov #{saved_state.id}, %rdi"
      %}
      {% for index in 0...8 %}
        {% lines << "add #{index * 8}(%rdi), %#{names[index].id}" %}
        {% lines << "mov %#{names[index].id}, #{index * 8}(%rdi)" %}
      {% end %}
      # The second block: eighty rounds from the table, eight per pass (a
      # loop small enough for the micro-op cache measured faster on Zen 3
      # than the eighty written out). With AVX-512, which here means one of
      # the wider cores (Intel since Ice Lake, AMD since Zen 4), each round
      # first adds h + K + W to d, then the Ch terms and Σ1, so the
      # dependence from e to the next e is four additions deep instead of
      # five; T1 is then the new e less the old d (one subtraction more).
      # That measured 1 to 2 percent faster on those cores and slower on
      # Zen 3, which has four integer units for 22 operations a round.
      {% if second_block %}
        {%
          lines << "lea 16(%rsp), %rdi"
          lines << "mov %rbx, %r14"
          lines << "xor %rcx, %r14"
          lines << "mov $$10, %rbp"
          lines << ".p2align 5"
          lines << "1:"
        %}
        {% for round in 0...8 %}
          {%
            a = names[(8 - round % 8) % 8]
            b = names[(9 - round % 8) % 8]
            d = names[(11 - round % 8) % 8]
            e = names[(12 - round % 8) % 8]
            f = names[(13 - round % 8) % 8]
            g = names[(14 - round % 8) % 8]
            h = names[(15 - round % 8) % 8]
            maj = round % 2 == 0 ? "r14" : "r15"
            term = round % 2 == 0 ? "r15" : "r14"
            lines << "add #{(round // 2) * 32 + (round % 2) * 8}(%rdi), %#{h.id}"
          %}
          {% if avx512 %}
            {%
              lines << "mov %#{d.id}, %rsi"
              lines << "add %#{h.id}, %#{d.id}"
              lines << "mov %#{f.id}, %#{term.id}"
              lines << "and %#{e.id}, %#{term.id}"
              lines << "rorx $$41, %#{e.id}, %r12"
              lines << "rorx $$18, %#{e.id}, %r13"
              lines << "add %#{term.id}, %#{d.id}"
              lines << "andn %#{g.id}, %#{e.id}, %#{term.id}"
              lines << "xor %r13, %r12"
              lines << "rorx $$14, %#{e.id}, %r13"
              lines << "add %#{term.id}, %#{d.id}"
              lines << "xor %r13, %r12"
              lines << "add %r12, %#{d.id}"
              lines << "mov %#{d.id}, %#{h.id}"
              lines << "sub %rsi, %#{h.id}"
              lines << "mov %#{a.id}, %#{term.id}"
              lines << "rorx $$39, %#{a.id}, %r12"
              lines << "xor %#{b.id}, %#{term.id}"
              lines << "rorx $$34, %#{a.id}, %r13"
              lines << "and %#{term.id}, %#{maj.id}"
              lines << "xor %r13, %r12"
              lines << "rorx $$28, %#{a.id}, %r13"
              lines << "xor %#{b.id}, %#{maj.id}"
              lines << "xor %r13, %r12"
              lines << "add %#{maj.id}, %#{h.id}"
              lines << "add %r12, %#{h.id}"
            %}
          {% else %}
            {%
              lines << "mov %#{f.id}, %#{term.id}"
              lines << "rorx $$41, %#{e.id}, %r12"
              lines << "rorx $$18, %#{e.id}, %r13"
              lines << "and %#{e.id}, %#{term.id}"
              lines << "xor %r13, %r12"
              lines << "rorx $$14, %#{e.id}, %r13"
              lines << "add %#{term.id}, %#{h.id}"
              lines << "andn %#{g.id}, %#{e.id}, %#{term.id}"
              lines << "xor %r13, %r12"
              lines << "add %#{term.id}, %#{h.id}"
              lines << "mov %#{a.id}, %#{term.id}"
              lines << "add %r12, %#{h.id}"
              lines << "rorx $$39, %#{a.id}, %r12"
              lines << "xor %#{b.id}, %#{term.id}"
              lines << "rorx $$34, %#{a.id}, %r13"
              lines << "add %#{h.id}, %#{d.id}"
              lines << "and %#{term.id}, %#{maj.id}"
              lines << "xor %r13, %r12"
              lines << "rorx $$28, %#{a.id}, %r13"
              lines << "xor %#{b.id}, %#{maj.id}"
              lines << "xor %r13, %r12"
              lines << "add %#{maj.id}, %#{h.id}"
              lines << "add %r12, %#{h.id}"
            %}
          {% end %}
        {% end %}
        {% lines = lines + ["add $$128, %rdi", "dec %rbp", "jnz 1b"] %}
        {% lines << "mov #{saved_state.id}, %rdi" %}
        {% for index in 0...8 %}
          {% lines << "add #{index * 8}(%rdi), %#{names[index].id}" %}
          {% lines << "mov %#{names[index].id}, #{index * 8}(%rdi)" %}
        {% end %}
      {% end %}
      {%
        lines << "vzeroupper"
        lines << "mov #{saved_message.id}, %rsi"
        lines << "mov #{saved_rsp.id}, %rsp"
        lines << "jmp 9f"
        lines << ".p2align 6"
        lines << "8:"
      %}
      # Each pair of round constants twice, once for each lane, then the
      # mask that puts the bytes of each 64-bit word in big-endian order.
      {% constants = round_constants.resolve %}
      {% for pair in 0...40 %}
        {% first = "#{constants[pair * 2]}".gsub(/_u64/, "") %}
        {% second = "#{constants[pair * 2 + 1]}".gsub(/_u64/, "") %}
        {% lines << ".quad #{first.id}, #{second.id}, #{first.id}, #{second.id}" %}
      {% end %}
      {%
        lines << ".quad 0x0001020304050607, 0x08090a0b0c0d0e0f, 0x0001020304050607, 0x08090a0b0c0d0e0f"
        lines << "9:"
      %}
      asm({{ lines.join("\n") }} :: "{rdi}"({{ state_pointer }}), "{rsi}"({{ block_pointer }}) : "rax", "rbx", "rcx", "rdx", "rbp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "ymm0", "ymm1", "ymm2", "ymm3", "ymm4", "ymm5", "ymm6", "ymm7", "ymm8", "ymm9", "ymm10", "ymm11", "ymm12", "memory", "flags")
    end
  end
end
