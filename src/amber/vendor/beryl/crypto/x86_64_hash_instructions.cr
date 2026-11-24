module Amber::Beryl::Crypto
  # :nodoc:
  #
  # The compression functions of SHA-1 and SHA-256 written with the SHA
  # extensions of x86-64 processors (Intel 64 and IA-32 Architectures
  # Software Developer's Manual, volume 2: `sha1rnds4`, `sha1nexte`,
  # `sha1msg1`, `sha1msg2`, `sha256rnds2`, `sha256msg1`, `sha256msg2`). Each
  # macro expands, inside the hash's `compress`, to one block of assembly
  # that mixes *block_count* whole blocks at *block_pointer* into the state
  # at *state_pointer*.
  #
  # Crystal has no vector types, so the instructions cannot be reached as
  # LLVM intrinsics; the assembly is written out here instead. It has one
  # branch, on the count of blocks left, and reads memory only at fixed
  # offsets from its three inputs, so its timing does not depend on the
  # message or the state. `scripts/check_secret_flow.rb` checks exactly that.
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
  end
end
