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
