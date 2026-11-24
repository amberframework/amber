module Amber::Beryl::Crypto
  # :nodoc:
  #
  # Comparisons and selections whose running time does not depend on the
  # values they work on. Each returns or takes a bit (0 or 1) rather than a
  # `Bool`, so no comparison of secrets turns into a branch.
  module ConstantTimeSelection
    # Returns 1 when *first* equals *second*, else 0.
    @[AlwaysInline]
    def self.equal_bit(first : UInt64, second : UInt64) : UInt64
      difference = first ^ second
      # The top bit of (d | -d) is set exactly when d is nonzero.
      ((difference | (0_u64 &- difference)) >> 63) ^ 1_u64
    end

    # Returns 1 when *first* < *second*, else 0.
    @[AlwaysInline]
    def self.less_than_bit(first : UInt64, second : UInt64) : UInt64
      difference = first.to_u128 &- second.to_u128
      (difference >> 127).to_u64!
    end

    # Returns 1 when every byte of *bytes* is zero, else 0.
    def self.all_zero_bit(bytes : Bytes) : UInt64
      accumulated = 0_u64
      bytes.each { |byte| accumulated |= byte }
      equal_bit(accumulated, 0_u64)
    end

    # Returns 1 when the big-endian number in *first* is less than the one in
    # *second* (both the same length), else 0. Reads every byte.
    def self.big_endian_less_than_bit(first : Bytes, second : Bytes) : UInt64
      is_less = 0_u64
      is_decided = 0_u64
      first.size.times do |index|
        left = first.unsafe_fetch(index).to_u64
        right = second.unsafe_fetch(index).to_u64
        byte_is_less = less_than_bit(left, right)
        byte_is_greater = less_than_bit(right, left)
        is_less |= byte_is_less & (is_decided ^ 1_u64)
        is_decided |= byte_is_less | byte_is_greater
      end
      is_less
    end

    # Returns a mask of all ones for a bit of 1, all zeros for 0, through a
    # value barrier so the optimizer keeps it a mask.
    @[AlwaysInline]
    def self.mask_of(bit : UInt64) : UInt64
      mask = 0_u64 &- bit
      barred = mask
      asm("" : "=r"(barred) : "0"(mask))
      barred
    end

    # Copies *source* over *destination* when *bit* is 1; leaves it when 0.
    def self.copy_if(bit : UInt64, destination : Bytes, source : Bytes) : Nil
      mask = mask_of(bit).to_u8!
      destination.size.times do |index|
        kept = destination.unsafe_fetch(index)
        destination[index] = kept ^ (mask & (kept ^ source.unsafe_fetch(index)))
      end
    end
  end
end
