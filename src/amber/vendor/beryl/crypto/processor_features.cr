module Amber::Beryl::Crypto
  # :nodoc:
  #
  # Tells which hash and cipher instructions the processor running this
  # program has, so that each algorithm can choose between its code written
  # with those instructions and its portable code.
  #
  # - Apple Silicon: every such processor has the SHA-1, SHA-256, SHA-512,
  #   AES and carry-less multiply (`pmull`) instructions, so the answer is
  #   known when the program is compiled.
  # - Linux on AArch64: the kernel lists them in the auxiliary vector, read
  #   once when the program starts.
  # - x86-64: CPUID lists the SHA extensions (SHA-1 and SHA-256),
  #   AES-NI and `pclmulqdq`, read once when the program starts.
  # - Anywhere else: none.
  #
  # The vector instructions ChaCha20 uses (Advanced SIMD on AArch64, SSE2
  # on x86-64) are part of both architectures, so they are present wherever
  # the architecture is.
  #
  # A program compiled with `-Dberyl_portable_hashes` runs the portable
  # hashes, and one compiled with `-Dberyl_portable_ciphers` the portable
  # ciphers; the test suite uses them to run every vector through the
  # portable code on a machine that has the instructions.
  module ProcessorFeatures
    {% if flag?(:aarch64) && flag?(:linux) %}
      lib LibAuxiliaryVector
        fun getauxval(type : LibC::ULong) : LibC::ULong
      end

      # `AT_HWCAP` and its `HWCAP_AES`, `HWCAP_PMULL`, `HWCAP_SHA1`,
      # `HWCAP_SHA2`, `HWCAP_SHA3` and `HWCAP_SHA512` bits
      # (Linux `arch/arm64/include/uapi/asm/hwcap.h`).
      private HARDWARE_CAPABILITIES_ENTRY = 16
      private AES_CAPABILITY              = 1_u64 << 3
      private PMULL_CAPABILITY            = 1_u64 << 4
      private SHA3_CAPABILITY             = 1_u64 << 17
      private SHA1_CAPABILITY             = 1_u64 << 5
      private SHA256_CAPABILITY           = 1_u64 << 6
      private SHA512_CAPABILITY           = 1_u64 << 21
      private DIT_CAPABILITY              = 1_u64 << 24

      private def self.has_capability?(capability : UInt64) : Bool
        LibAuxiliaryVector.getauxval(HARDWARE_CAPABILITIES_ENTRY).to_u64 & capability != 0
      end
    {% elsif flag?(:x86_64) %}
      # Returns the EAX, EBX, ECX and EDX registers that CPUID gives for
      # *leaf* and *subleaf*.
      private def self.processor_identification(leaf : UInt32, subleaf : UInt32) : {UInt32, UInt32, UInt32, UInt32}
        eax = 0_u32
        ebx = 0_u32
        ecx = 0_u32
        edx = 0_u32
        asm("cpuid" : "={eax}"(eax), "={ebx}"(ebx), "={ecx}"(ecx), "={edx}"(edx) : "{eax}"(leaf), "{ecx}"(subleaf))
        {eax, ebx, ecx, edx}
      end

      # The SHA extensions are bit 29 of EBX in leaf 7; the routines also use
      # SSSE3 (`pshufb`, `palignr`) and SSE4.1 (`pblendw`, `pinsrd`,
      # `pextrd`), bits 9 and 19 of ECX in leaf 1.
      private def self.has_sha_extensions? : Bool
        highest_leaf = processor_identification(0_u32, 0_u32)[0]
        return false if highest_leaf < 7

        feature_bits = processor_identification(1_u32, 0_u32)[2]
        extended_feature_bits = processor_identification(7_u32, 0_u32)[1]
        feature_bits.bit(9) == 1 && feature_bits.bit(19) == 1 && extended_feature_bits.bit(29) == 1
      end

      # AES-NI is bit 25 and `pclmulqdq` bit 1 of ECX in leaf 1; the cipher
      # routines also use SSSE3 (`pshufb`) and SSE4.1 (`pinsrd`), bits 9 and
      # 19.
      private def self.has_cipher_bit?(bit : Int32) : Bool
        feature_bits = processor_identification(1_u32, 0_u32)[2]
        feature_bits.bit(bit) == 1 && feature_bits.bit(9) == 1 && feature_bits.bit(19) == 1
      end

      # XCR0, the register that says which register state the operating
      # system saves on a context switch (`xgetbv` with ECX 0). Only read
      # once OSXSAVE (bit 27 of ECX in leaf 1) says `xgetbv` is allowed.
      private def self.extended_control_register : UInt64
        low = 0_u32
        high = 0_u32
        asm("xgetbv" : "={eax}"(low), "={edx}"(high) : "{ecx}"(0_u32))
        (high.to_u64 << 32) | low.to_u64
      end

      # Whether the operating system saves the 256-bit YMM registers (XCR0
      # bits 1 and 2), which AVX and AVX2 need.
      private def self.saves_256_bit_registers? : Bool
        feature_bits = processor_identification(1_u32, 0_u32)[2]
        return false unless feature_bits.bit(27) == 1 && feature_bits.bit(28) == 1

        extended_control_register & 0b110 == 0b110
      end

      # Whether the operating system also saves the AVX-512 state: the
      # opmask registers and both halves of the 512-bit ZMM registers (XCR0
      # bits 5, 6 and 7).
      private def self.saves_512_bit_registers? : Bool
        saves_256_bit_registers? && extended_control_register & 0b1110_0110 == 0b1110_0110
      end

      # Bit *bit* of EBX (*register* 1) or ECX (*register* 2) in leaf 7,
      # subleaf 0, or false where the processor has no leaf 7.
      private def self.has_leaf7_bit?(register : Int32, bit : Int32) : Bool
        highest_leaf = processor_identification(0_u32, 0_u32)[0]
        return false if highest_leaf < 7

        processor_identification(7_u32, 0_u32)[register].bit(bit) == 1
      end

      # Whether the processor is AMD's family 19h (Zen 3 and Zen 4): the
      # vendor string of leaf 0 is "AuthenticAMD", and the family of leaf 1
      # (its base, 0Fh, plus the extended family) is 19h.
      private def self.amd_family_19h? : Bool
        _, ebx, ecx, edx = processor_identification(0_u32, 0_u32)
        return false unless ebx == 0x68747541_u32 && edx == 0x69746e65_u32 && ecx == 0x444d4163_u32

        signature = processor_identification(1_u32, 0_u32)[0]
        base_family = (signature >> 8) & 0xf_u32
        extended_family = (signature >> 20) & 0xff_u32
        base_family == 0xf_u32 && base_family + extended_family == 0x19_u32
      end
    {% end %}

    {% if flag?(:beryl_portable_hashes) %}
      HAS_SHA1_INSTRUCTIONS   = false
      HAS_SHA256_INSTRUCTIONS = false
      HAS_SHA512_INSTRUCTIONS = false
    {% elsif flag?(:aarch64) && flag?(:darwin) %}
      HAS_SHA1_INSTRUCTIONS   = true
      HAS_SHA256_INSTRUCTIONS = true
      HAS_SHA512_INSTRUCTIONS = true
    {% elsif flag?(:aarch64) && flag?(:linux) %}
      HAS_SHA1_INSTRUCTIONS   = has_capability?(SHA1_CAPABILITY)
      HAS_SHA256_INSTRUCTIONS = has_capability?(SHA256_CAPABILITY)
      HAS_SHA512_INSTRUCTIONS = has_capability?(SHA512_CAPABILITY)
    {% elsif flag?(:x86_64) %}
      HAS_SHA1_INSTRUCTIONS   = has_sha_extensions?
      HAS_SHA256_INSTRUCTIONS = HAS_SHA1_INSTRUCTIONS
      HAS_SHA512_INSTRUCTIONS = false
    {% else %}
      HAS_SHA1_INSTRUCTIONS   = false
      HAS_SHA256_INSTRUCTIONS = false
      HAS_SHA512_INSTRUCTIONS = false
    {% end %}

    {% if flag?(:beryl_portable_ciphers) %}
      HAS_AES_INSTRUCTIONS                = false
      HAS_CARRYLESS_MULTIPLY_INSTRUCTIONS = false
      HAS_VECTOR_INSTRUCTIONS             = false
    {% elsif flag?(:aarch64) && flag?(:darwin) %}
      HAS_AES_INSTRUCTIONS                = true
      HAS_CARRYLESS_MULTIPLY_INSTRUCTIONS = true
      HAS_VECTOR_INSTRUCTIONS             = true
    {% elsif flag?(:aarch64) && flag?(:linux) %}
      HAS_AES_INSTRUCTIONS                = has_capability?(AES_CAPABILITY)
      HAS_CARRYLESS_MULTIPLY_INSTRUCTIONS = has_capability?(PMULL_CAPABILITY)
      HAS_VECTOR_INSTRUCTIONS             = true
    {% elsif flag?(:x86_64) %}
      HAS_AES_INSTRUCTIONS                = has_cipher_bit?(25)
      HAS_CARRYLESS_MULTIPLY_INSTRUCTIONS = has_cipher_bit?(1)
      HAS_VECTOR_INSTRUCTIONS             = true
    {% else %}
      HAS_AES_INSTRUCTIONS                = false
      HAS_CARRYLESS_MULTIPLY_INSTRUCTIONS = false
      HAS_VECTOR_INSTRUCTIONS             = false
    {% end %}

    # The wider x86-64 vector and integer instructions, each found through
    # CPUID and, for the vector registers, XCR0 (the operating system must
    # save them):
    #
    # - `HAS_AVX2`: AVX2 (bit 5 of EBX in leaf 7), on 256-bit registers.
    # - `HAS_AVX512`: AVX-512 Foundation, DQ, BW and VL (bits 16, 17, 30 and
    #   31 of EBX in leaf 7), on 512-bit registers with opmasks.
    # - `HAS_VECTOR_AES`: VAES (bit 9 of ECX in leaf 7), AES rounds on every
    #   128-bit lane of a 256-bit (or, with AVX-512, 512-bit) register;
    #   only set with AVX2 and AES-NI.
    # - `HAS_VECTOR_CARRYLESS_MULTIPLY`: VPCLMULQDQ (bit 10 of ECX in leaf
    #   7), the carry-less multiply on every lane; only set with AVX2 and
    #   `pclmulqdq`.
    # - `HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS`: BMI2 (`mulx`, bit 8 of
    #   EBX in leaf 7) and ADX (`adcx`, `adox`, bit 19), for multiplication
    #   with two independent carry chains.
    # - `HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD`: AVX-512 IFMA (bit 21 of EBX
    #   in leaf 7), 52-bit multiply-add, only set with `HAS_AVX512`.
    # - `SPLITS_512_BIT_OPERATIONS`: the processor runs each 512-bit
    #   instruction as two 256-bit halves, as Zen 4 does (AMD family 19h with
    #   AVX-512; Zen 3, the same family, has no AVX-512). Where a 512-bit
    #   path saves little, such a processor takes the narrower one.
    #
    # `-Dberyl_without_avx512` keeps every 512-bit path off,
    # `-Dberyl_without_avx2` every 256-bit and 512-bit path (VAES and
    # VPCLMULQDQ included), and `-Dberyl_without_mulx` the BMI2 and ADX
    # path, so the test suite runs each narrower path on a processor that
    # has the wider one. `-Dberyl_portable_rsa` turns off the multiplication
    # flag; `HAS_VECTOR_AES` and `HAS_VECTOR_CARRYLESS_MULTIPLY` follow
    # `-Dberyl_portable_ciphers` through the older flags, and each algorithm
    # checks its own `-Dberyl_portable_*` flag before taking an AVX2 or
    # AVX-512 path.
    {% if flag?(:x86_64) && !flag?(:beryl_without_avx2) %}
      HAS_AVX2 = saves_256_bit_registers? && has_leaf7_bit?(1, 5)
    {% else %}
      HAS_AVX2 = false
    {% end %}

    {% if flag?(:x86_64) && !flag?(:beryl_without_avx2) && !flag?(:beryl_without_avx512) %}
      HAS_AVX512 = HAS_AVX2 && saves_512_bit_registers? &&
                   has_leaf7_bit?(1, 16) && has_leaf7_bit?(1, 17) && has_leaf7_bit?(1, 30) && has_leaf7_bit?(1, 31)
      HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD = HAS_AVX512 && has_leaf7_bit?(1, 21)
      SPLITS_512_BIT_OPERATIONS             = HAS_AVX512 && amd_family_19h?
    {% else %}
      HAS_AVX512                            = false
      HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD = false
      SPLITS_512_BIT_OPERATIONS             = false
    {% end %}

    {% if flag?(:x86_64) %}
      HAS_VECTOR_AES                = HAS_AVX2 && HAS_AES_INSTRUCTIONS && has_leaf7_bit?(2, 9)
      HAS_VECTOR_CARRYLESS_MULTIPLY = HAS_AVX2 && HAS_CARRYLESS_MULTIPLY_INSTRUCTIONS && has_leaf7_bit?(2, 10)
    {% else %}
      HAS_VECTOR_AES                = false
      HAS_VECTOR_CARRYLESS_MULTIPLY = false
    {% end %}

    # Whether the processor has the bit manipulation instructions BMI1
    # (`andn`, bit 3 of EBX in leaf 7) and BMI2 (`rorx`, bit 8), which the
    # rounds of the x86-64 SHA-512 code use. They change no register width,
    # so no flag turns them off on their own; the hashes that use them
    # follow `-Dberyl_portable_hashes` and `HAS_AVX2`.
    {% if flag?(:x86_64) %}
      HAS_BIT_MANIPULATION_INSTRUCTIONS = has_leaf7_bit?(1, 3) && has_leaf7_bit?(1, 8)
    {% else %}
      HAS_BIT_MANIPULATION_INSTRUCTIONS = false
    {% end %}

    {% if flag?(:x86_64) && !flag?(:beryl_portable_rsa) && !flag?(:beryl_without_mulx) %}
      HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS = has_leaf7_bit?(1, 8) && has_leaf7_bit?(1, 19)
    {% else %}
      HAS_WIDE_MULTIPLY_WITH_TWO_CARRY_CHAINS = false
    {% end %}

    # Whether the processor has `eor3`, which XORs three registers in one
    # instruction (the SHA3 extension of ARMv8.2). The AArch64 GHASH and
    # counter mode use it where it is present; `-Dberyl_without_eor3` runs
    # the code written without it, so the test suite covers both.
    {% if flag?(:beryl_without_eor3) %}
      HAS_THREE_WAY_EXCLUSIVE_OR = false
    {% elsif flag?(:aarch64) && flag?(:darwin) %}
      HAS_THREE_WAY_EXCLUSIVE_OR = true
    {% elsif flag?(:aarch64) && flag?(:linux) %}
      HAS_THREE_WAY_EXCLUSIVE_OR = has_capability?(SHA3_CAPABILITY)
    {% else %}
      HAS_THREE_WAY_EXCLUSIVE_OR = false
    {% end %}

    # Whether Poly1305 multiplies 64-bit words into 128-bit products, which
    # both 64-bit architectures do in one or two instructions whose time does
    # not depend on the words.
    {% if flag?(:beryl_portable_ciphers) %}
      HAS_WIDE_MULTIPLICATION = false
    {% elsif flag?(:aarch64) || flag?(:x86_64) %}
      HAS_WIDE_MULTIPLICATION = true
    {% else %}
      HAS_WIDE_MULTIPLICATION = false
    {% end %}

    # Whether the processor has Data Independent Timing (FEAT_DIT, Armv8.4):
    # a mode in which the time of data-processing instructions does not
    # depend on the values they work on. Every Apple Silicon processor has
    # it; Linux lists it as `HWCAP_DIT`. See `DataIndependentTiming`.
    # `-Dberyl_without_data_independent_timing` leaves the mode alone, for
    # running under Valgrind, whose AArch64 decoder does not know the DIT
    # register; the instructions in between are the same either way.
    {% if flag?(:beryl_without_data_independent_timing) %}
      HAS_DATA_INDEPENDENT_TIMING = false
    {% elsif flag?(:aarch64) && flag?(:darwin) %}
      HAS_DATA_INDEPENDENT_TIMING = true
    {% elsif flag?(:aarch64) && flag?(:linux) %}
      HAS_DATA_INDEPENDENT_TIMING = has_capability?(DIT_CAPABILITY)
    {% else %}
      HAS_DATA_INDEPENDENT_TIMING = false
    {% end %}

    # Whether AES-GCM runs on the processor's instructions: it needs both
    # AES and the carry-less multiply.
    HAS_GALOIS_COUNTER_MODE_INSTRUCTIONS = HAS_AES_INSTRUCTIONS && HAS_CARRYLESS_MULTIPLY_INSTRUCTIONS
  end
end
