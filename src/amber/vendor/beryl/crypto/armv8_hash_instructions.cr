module Amber::Beryl::Crypto
  # :nodoc:
  #
  # The compression functions of SHA-1, SHA-256 and SHA-512 written with the
  # hash instructions of ARMv8 processors (the SHA1, SHA2 and SHA512
  # extensions, Arm Architecture Reference Manual C7.2). Each macro expands,
  # inside the hash's `compress`, to one block of assembly that mixes
  # *block_count* whole blocks at *block_pointer* into the state at
  # *state_pointer*.
  #
  # Crystal has no vector types, so the instructions cannot be reached as
  # LLVM intrinsics; the assembly is written out here instead. It has one
  # branch, on the count of blocks left, and reads memory only at fixed
  # offsets from its three inputs, so its timing does not depend on the
  # message or the state. `scripts/check_secret_flow.rb` checks exactly that.
  #
  # Registers: x9 state, x10 message, x11 blocks left, x12 round constants;
  # v8 to v15 are left alone because the calling convention preserves them.
  module Armv8HashInstructions
    # SHA-256 (also SHA-224). v0 holds a, b, c, d and v1 holds e, f, g, h;
    # `sha256h` and `sha256h2` run four rounds each on one half. v4 to v7
    # hold sixteen message words, renewed four at a time by `sha256su0` and
    # `sha256su1`. *round_constants* names the 64 constants of FIPS 180-4
    # §4.2.2.
    macro compress_sha256_blocks(state_pointer, block_pointer, block_count, round_constants)
      {% template = "
  .arch_extension sha2
  mov x9, $0
  mov x10, $1
  mov x11, $2
  adr x12, 8f
  ld1 {v0.4s, v1.4s}, [x9]
1:
  ld1 {v4.16b, v5.16b, v6.16b, v7.16b}, [x10], #64
  mov v16.16b, v0.16b
  mov v17.16b, v1.16b
  rev32 v4.16b, v4.16b
  rev32 v5.16b, v5.16b
  rev32 v6.16b, v6.16b
  rev32 v7.16b, v7.16b
" %}
      {% for quad in 0...16 %}
        {% words = 4 + quad % 4 %}
        {% template = template + "  ldr q18, [x12, ##{quad * 16}]\n  add v3.4s, v#{words}.4s, v18.4s\n" %}
        {% if quad < 12 %}
          {% template = template + "  sha256su0 v#{words}.4s, v#{4 + (quad + 1) % 4}.4s\n" %}
        {% end %}
        {% template = template + "  mov v2.16b, v0.16b\n  sha256h q0, q1, v3.4s\n  sha256h2 q1, q2, v3.4s\n" %}
        {% if quad < 12 %}
          {% template = template + "  sha256su1 v#{words}.4s, v#{4 + (quad + 2) % 4}.4s, v#{4 + (quad + 3) % 4}.4s\n" %}
        {% end %}
      {% end %}
      {% template = template + "  add v0.4s, v0.4s, v16.4s
  add v1.4s, v1.4s, v17.4s
  subs x11, x11, #1
  b.ne 1b
  st1 {v0.4s, v1.4s}, [x9]
  b 9f
8:
" %}
      {% for constant in round_constants.resolve %}
        {% template = template + "  .long #{constant}\n".gsub(/_u32/, "") %}
      {% end %}
      {% template = template + "9:\n" %}
      asm({{ template }} :: "r"({{ state_pointer }}), "r"({{ block_pointer }}), "r"({{ block_count }}) : "x9", "x10", "x11", "x12", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16", "v17", "v18", "memory", "cc")
    end

    # SHA-512 (also SHA-384 and SHA-512/256). The state lives in four of the
    # five registers v0 to v4 as the pairs (a, b), (c, d), (e, f), (g, h), and
    # the registers trade roles after each pair of rounds instead of moving
    # their contents. v16 to v23 hold sixteen message words, renewed two at a
    # time by `sha512su0` and `sha512su1`. *round_constants* names the 80
    # constants of FIPS 180-4 §4.2.3.
    #
    # `sha512h` computes T1 for two rounds from (e, f, g) and from the sum it
    # is given, and adds the low half of its last operand to the first T1 to
    # form the next e on the way. Here that sum already includes c and d
    # (h + K + W + d and g + K + W + c) and the low half of the last operand
    # is zero, so `sha512h` returns the next (e, f) itself. The longest chain
    # from one pair of rounds to the next is then `sha512h` and one `ext`;
    # T1 alone, which `sha512h2` needs for the next (a, b), is that result
    # minus (c, d), off the chain.
    macro compress_sha512_blocks(state_pointer, block_pointer, block_count, round_constants)
      {% template = "
  .arch_extension sha3
  mov x9, $0
  mov x10, $1
  mov x11, $2
  adr x12, 8f
  ld1 {v0.2d, v1.2d, v2.2d, v3.2d}, [x9]
  movi v29.2d, #0
1:
  ld1 {v16.16b, v17.16b, v18.16b, v19.16b}, [x10], #64
  ld1 {v20.16b, v21.16b, v22.16b, v23.16b}, [x10], #64
  mov v24.16b, v0.16b
  mov v25.16b, v1.16b
  mov v26.16b, v2.16b
  mov v27.16b, v3.16b
" %}
      {% for register in 16...24 %}
        {% template = template + "  rev64 v#{register}.16b, v#{register}.16b\n" %}
      {% end %}
      {% roles = [0, 1, 2, 3, 4] %}
      {% for pair in 0...40 %}
        {% ab = roles[0] %}
        {% cd = roles[1] %}
        {% ef = roles[2] %}
        {% gh = roles[3] %}
        {% spare = roles[4] %}
        {% words = 16 + pair % 8 %}
        {% template = template + "  ldr q28, [x12, ##{pair * 16}]
  add v5.2d, v28.2d, v#{words}.2d
  ext v6.16b, v#{ef}.16b, v#{gh}.16b, #8
  ext v5.16b, v5.16b, v5.16b, #8
  ext v7.16b, v29.16b, v#{ef}.16b, #8
  add v#{gh}.2d, v#{gh}.2d, v5.2d
  add v#{gh}.2d, v#{gh}.2d, v#{cd}.2d
" %}
        {% if pair < 32 %}
          {% template = template + "  ext v5.16b, v#{16 + (pair + 4) % 8}.16b, v#{16 + (pair + 5) % 8}.16b, #8
  sha512su0 v#{words}.2d, v#{16 + (pair + 1) % 8}.2d
" %}
        {% end %}
        {% template = template + "  sha512h q#{gh}, q6, v7.2d\n" %}
        {% if pair < 32 %}
          {% template = template + "  sha512su1 v#{words}.2d, v#{16 + (pair + 7) % 8}.2d, v5.2d\n" %}
        {% end %}
        {% template = template + "  sub v#{spare}.2d, v#{gh}.2d, v#{cd}.2d\n  sha512h2 q#{spare}, q#{cd}, v#{ab}.2d\n" %}
        {% roles = [spare, ab, gh, ef, cd] %}
      {% end %}
      {% # After forty pairs of rounds (a, b) is in v4 and (c, d) in v0; v1 is
# free, so (c, d) is summed into it before v0 is overwritten.
  %}
      {% template = template + "  add v1.2d, v#{roles[1]}.2d, v25.2d
  add v0.2d, v#{roles[0]}.2d, v24.2d
  add v2.2d, v#{roles[2]}.2d, v26.2d
  add v3.2d, v#{roles[3]}.2d, v27.2d
  subs x11, x11, #1
  b.ne 1b
  st1 {v0.2d, v1.2d, v2.2d, v3.2d}, [x9]
  b 9f
8:
" %}
      {% for constant in round_constants.resolve %}
        {% template = template + "  .quad #{constant}\n".gsub(/_u64/, "") %}
      {% end %}
      {% template = template + "9:\n" %}
      asm({{ template }} :: "r"({{ state_pointer }}), "r"({{ block_pointer }}), "r"({{ block_count }}) : "x9", "x10", "x11", "x12", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "memory", "cc")
    end

    # SHA-1. v0 holds a, b, c, d; `sha1c`, `sha1p` and `sha1m` run four
    # rounds with the choice, parity and majority functions, and `sha1h`
    # produces the e they need next. v4 to v7 hold sixteen message words,
    # renewed four at a time by `sha1su0` and `sha1su1`; v20 to v23 hold the
    # four round constants of FIPS 180-4 §4.2.1.
    macro compress_sha1_blocks(state_pointer, block_pointer, block_count)
      {% template = "
  .arch_extension sha2
  mov x9, $0
  mov x10, $1
  mov x11, $2
  ld1 {v0.4s}, [x9]
  ldr s1, [x9, #16]
  movz w12, #0x7999
  movk w12, #0x5a82, lsl #16
  dup v20.4s, w12
  movz w12, #0xeba1
  movk w12, #0x6ed9, lsl #16
  dup v21.4s, w12
  movz w12, #0xbcdc
  movk w12, #0x8f1b, lsl #16
  dup v22.4s, w12
  movz w12, #0xc1d6
  movk w12, #0xca62, lsl #16
  dup v23.4s, w12
1:
  ld1 {v4.16b, v5.16b, v6.16b, v7.16b}, [x10], #64
  mov v16.16b, v0.16b
  mov v17.16b, v1.16b
  rev32 v4.16b, v4.16b
  rev32 v5.16b, v5.16b
  rev32 v6.16b, v6.16b
  rev32 v7.16b, v7.16b
" %}
      {% for quad in 0...20 %}
        {% words = 4 + quad % 4 %}
        {% mixing = quad < 5 ? "c" : (quad >= 10 && quad < 15 ? "m" : "p") %}
        {% template = template + "  add v3.4s, v#{words}.4s, v#{20 + quad // 5}.4s
  sha1h s#{2 - quad % 2}, s0
  sha1#{mixing.id} q0, s#{1 + quad % 2}, v3.4s
" %}
        {% if quad < 16 %}
          {% template = template + "  sha1su0 v#{words}.4s, v#{4 + (quad + 1) % 4}.4s, v#{4 + (quad + 2) % 4}.4s
  sha1su1 v#{words}.4s, v#{4 + (quad + 3) % 4}.4s
" %}
        {% end %}
      {% end %}
      {% template = template + "  add v0.4s, v0.4s, v16.4s
  add v1.4s, v1.4s, v17.4s
  subs x11, x11, #1
  b.ne 1b
  st1 {v0.4s}, [x9]
  str s1, [x9, #16]
" %}
      asm({{ template }} :: "r"({{ state_pointer }}), "r"({{ block_pointer }}), "r"({{ block_count }}) : "x9", "x10", "x11", "x12", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16", "v17", "v20", "v21", "v22", "v23", "memory", "cc")
    end
  end
end
