module Amber::Mica::Core
  # Byte-run scanning and copying for the hot paths of format scanners and
  # trees (text runs, attribute values, names, stored values).
  #
  # This is the one place in Mica that touches bytes without a bounds check
  # on every access: each method checks its whole window against the slice
  # once, before it reads or writes, and never leaves that window.
  # Everything else goes through checked `Slice` indexing.
  module ByteScan
    # Returns the index of the first byte in `bytes[from...stop]` for which
    # the block returns false, or *stop* when it returns true for all of
    # them. Raises `IndexError` unless `0 <= from <= stop <= bytes.size`.
    #
    # ```
    # Amber::Mica::Core::ByteScan.skip_while("abc;d".to_slice, 0, 5) { |byte| byte != ';'.ord } # => 3
    # ```
    @[AlwaysInline]
    def self.skip_while(bytes : Bytes, from : Int32, stop : Int32, & : UInt8 -> Bool) : Int32
      unless 0 <= from && from <= stop && stop <= bytes.size
        raise IndexError.new("Scan window #{from}...#{stop} is outside 0...#{bytes.size}")
      end
      index = from
      # from <= index < stop <= bytes.size, so every read is in bounds.
      while index < stop && yield bytes.unsafe_fetch(index)
        index += 1
      end
      index
    end

    # Returns the index of the first byte in `bytes[from...stop]` that is
    # not ASCII (0x80 or above), or *stop* when all of them are. Reads eight
    # bytes at a time while they fit. Raises `IndexError` unless
    # `0 <= from <= stop <= bytes.size`.
    #
    # ```
    # Amber::Mica::Core::ByteScan.skip_ascii("plain text é".to_slice, 0, 13) # => 11
    # ```
    def self.skip_ascii(bytes : Bytes, from : Int32, stop : Int32) : Int32
      unless 0 <= from && from <= stop && stop <= bytes.size
        raise IndexError.new("Scan window #{from}...#{stop} is outside 0...#{bytes.size}")
      end
      index = from
      pointer = bytes.to_unsafe
      # index + 8 <= stop <= bytes.size: the word read is in bounds (an
      # unaligned load, which the targets Mica supports allow).
      while index + 8 <= stop
        break if (pointer + index).as(Pointer(UInt64)).value & 0x8080808080808080_u64 != 0
        index += 8
      end
      while index < stop && pointer[index] < 0x80
        index += 1
      end
      index
    end

    # Returns true when the `expected.size` bytes of *bytes* at *offset*
    # equal *expected*. Raises `IndexError` unless
    # `0 <= offset <= bytes.size - expected.size`. Compares in place, which
    # beats building a slice and calling memcmp for short names.
    #
    # ```
    # Amber::Mica::Core::ByteScan.matches?("<a></a>".to_slice, 5, "a".to_slice) # => true
    # ```
    @[AlwaysInline]
    def self.matches?(bytes : Bytes, offset : Int32, expected : Bytes) : Bool
      size = expected.size
      unless 0 <= offset && offset <= bytes.size - size
        raise IndexError.new("Window #{offset}...#{offset + size} is outside 0...#{bytes.size}")
      end
      index = 0
      # 0 <= index < size, offset + size <= bytes.size: both reads in bounds.
      while index < size
        return false unless bytes.unsafe_fetch(offset + index) == expected.unsafe_fetch(index)
        index += 1
      end
      true
    end

    # Copies all of *source* into *target* starting at *offset*, without
    # building a subslice. Raises `IndexError` unless
    # `0 <= offset <= target.size - source.size`, and when *target* is
    # read-only.
    #
    # ```
    # target = Bytes.new(4)
    # Amber::Mica::Core::ByteScan.copy_into(target, 1, "ab".to_slice)
    # target # => Bytes[0, 97, 98, 0]
    # ```
    @[AlwaysInline]
    def self.copy_into(target : Bytes, offset : Int32, source : Bytes) : Nil
      size = source.size
      unless 0 <= offset && offset <= target.size - size
        raise IndexError.new("Window #{offset}...#{offset + size} is outside 0...#{target.size}")
      end
      raise IndexError.new("Copy into a read-only slice") if target.read_only?
      # offset + size <= target.size: the copy stays inside target.
      source.copy_to(target.to_unsafe + offset, size)
    end
  end
end
