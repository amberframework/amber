require "./processor_features"

module Amber::Beryl::Crypto
  # :nodoc:
  #
  # Runs work on secrets with the processor's Data Independent Timing mode
  # on (PSTATE.DIT, Armv8.4). Without it, Arm allows a data-processing
  # instruction to take a time that depends on its operands, and on Apple
  # M4 it does: an X25519 multiplication by a scalar with few set bits ran
  # measurably faster than by a random scalar, although the compiled code
  # has no branch and no table index that depends on the scalar
  # (spec/constant_time/public_key_timing_spec.cr). With DIT on, the two
  # cannot be told apart. Apple asks for DIT around cryptographic work.
  #
  # The mode belongs to the thread. `run` turns it on when it is off and
  # leaves it on: turning it off again after each call cost about 17 ns
  # on Apple M4 (one `msr` each way), half as long as SHA-256 takes on
  # a 64-byte message, while code that runs with the mode on was measured no
  # slower (HMAC-SHA-256 and SHA-256 on 64 bytes, 65 ns and 35 ns either
  # way). Reading the mode costs about 0.5 ns, so calls that nest, such as
  # HMAC inside HKDF, pay almost nothing. Processors without the mode
  # (x86-64, older Arm) run the block as it is.
  module DataIndependentTiming
    def self.run(&)
      {% if flag?(:aarch64) %}
        turn_on_unless_on if ProcessorFeatures::HAS_DATA_INDEPENDENT_TIMING
      {% end %}
      yield
    end

    {% if flag?(:aarch64) %}
      # `mrs x0, dit` and `msr dit, #1`, written as their encodings so that
      # no assembler target feature is needed. The branch is on the mode,
      # which is public.
      @[AlwaysInline]
      private def self.turn_on_unless_on : Nil
        state = 0_u64
        asm(".inst 0xd53b42a0" : "={x0}"(state) :: "memory" : "volatile")
        asm(".inst 0xd503415f" :::: "volatile") unless state.bit(24) == 1
      end
    {% end %}
  end
end
