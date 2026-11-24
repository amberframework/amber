module Amber::Mica::Brotli
  # The encoder's side of RFC 7932's length and distance codes: from a
  # length or distance to its code, the inverse of the decoder's tables.
  #
  # :nodoc:
  module EncoderCodes
    # The insert-and-copy cell (2 to 10) for insert code group and copy
    # code group (each 0 to 2), when the distance is written.
    EXPLICIT_CELL = StaticArray[2, 3, 6, 4, 5, 8, 7, 9, 10]

    def self.insert_code(length : Int32) : Int32
      if length < 6
        length
      elsif length < 130
        bits = MatchFinder.log2_floor(length - 2) - 1
        (bits << 1) + ((length - 2) >> bits) + 2
      elsif length < 2114
        MatchFinder.log2_floor(length - 66) + 10
      elsif length < 6210
        21
      elsif length < 22594
        22
      else
        23
      end
    end

    def self.copy_code(length : Int32) : Int32
      if length < 10
        length - 2
      elsif length < 134
        bits = MatchFinder.log2_floor(length - 6) - 1
        (bits << 1) + ((length - 6) >> bits) + 4
      elsif length < 2118
        MatchFinder.log2_floor(length - 70) + 12
      else
        23
      end
    end

    # The insert-and-copy symbol; with *implicit*, cells 0 and 1 (which
    # reuse the last distance and write none) when the codes fit them.
    def self.command_symbol(insert_code : Int32, copy_code : Int32, implicit : Bool) : Int32
      cell =
        if implicit && insert_code < 8 && copy_code < 16
          copy_code < 8 ? 0 : 1
        else
          EXPLICIT_CELL[(insert_code >> 3) * 3 + (copy_code >> 3)]
        end
      (cell << 6) | ((insert_code & 7) << 3) | (copy_code & 7)
    end

    # The distance symbol (NPOSTFIX 0, NDIRECT 0) and its extra bits for
    # *distance*, as {symbol, extra bit count, extra value}.
    def self.distance_symbol(distance : Int32) : {Int32, Int32, Int32}
      value = distance + 3
      bits = MatchFinder.log2_floor(value) - 1
      prefix = (value >> bits) & 1
      {16 + 2 * (bits - 1) + prefix, bits, value - ((2 + prefix) << bits)}
    end

    # The short distance code (0 to 15) that gives *distance* from the
    # last four distances, or -1.
    def self.short_distance_code(distance : Int32, cache : StaticArray(Int32, 4)) : Int32
      4.times { |slot| return slot if distance == cache[slot] }
      2.times do |slot|
        delta = distance - cache[slot]
        next unless -3 <= delta <= 3
        return 4 + slot * 6 + (delta < 0 ? (-delta - 1) * 2 : (delta - 1) * 2 + 1)
      end
      -1
    end

    def self.block_count_code(length : Int32) : Int32
      code = 0
      while code < 25 && length >= Decoder::BLOCK_LENGTH_BASE[code + 1]
        code += 1
      end
      code
    end

    # MNIBBLES for a metablock of *length* bytes.
    def self.length_nibbles(length : Int32) : Int32
      last = length - 1
      if last < (1 << 16)
        4
      elsif last < (1 << 20)
        5
      else
        6
      end
    end
  end
end
