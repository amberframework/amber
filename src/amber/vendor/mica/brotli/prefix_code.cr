module Amber::Mica::Brotli
  # Builds two-level lookup tables for canonical prefix codes (RFC 7932,
  # section 3.2) into a shared `Store`.
  #
  # An entry is a `UInt32`: the symbol in the upper 24 bits and a bit
  # count in the lower 8. The root level is indexed by the next
  # `ROOT_BITS` bits of input (least significant bit first, as Brotli
  # packs codes). A root entry whose count is above `ROOT_BITS` points to
  # a second-level table: its symbol field is that table's offset from the
  # root's start and its count is `ROOT_BITS` plus the second level's
  # index width. Second-level entries hold the code length minus
  # `ROOT_BITS`.
  #
  # :nodoc:
  module PrefixCode
    ROOT_BITS = 8
    ROOT_SIZE = 1 << ROOT_BITS
    # The longest code length Brotli allows.
    MAX_LENGTH = 15

    # The tables of one metablock header, end to end.
    class Store
      getter size : Int32 = 0

      def initialize
        @entries = Slice(UInt32).new(4_096)
      end

      def to_unsafe : Pointer(UInt32)
        @entries.to_unsafe
      end

      def clear : Nil
        @size = 0
      end

      # Drops every entry from *size* on.
      def truncate(size : Int32) : Nil
        @size = size
      end

      # Adds *count* entries at the end and returns where they start.
      def append(count : Int32) : Int32
        start = @size
        needed = start + count
        if needed > @entries.size
          capacity = @entries.size
          while capacity < needed
            capacity <<= 1
          end
          grown = Slice(UInt32).new(capacity)
          grown.copy_from(@entries.to_unsafe, start)
          @entries = grown
        end
        @size = needed
        start
      end
    end

    # Appends the table for the code with *lengths* (one entry per symbol
    # of the alphabet, 0 for an unused symbol) to *store* and returns where
    # it starts. See `build_from_list`.
    def self.build(lengths : Slice(UInt8), store : Store, sorted : Slice(UInt16), symbols : Slice(UInt16)) : Int32
      count = StaticArray(Int32, 16).new(0)
      used = 0
      lengths.each_with_index do |length, symbol|
        next if length == 0
        count[length] += 1
        symbols[used] = symbol.to_u16
        used += 1
      end
      build_from_list(symbols, lengths, used, count, store, sorted)
    end

    # Appends the table for a code to *store* and returns where it starts.
    # *symbols* lists the first *used* symbols with a nonzero length in
    # increasing order, *lengths* gives each symbol's length (indexed by
    # symbol) and *count* the number of symbols of each length. The code
    # must be complete (the caller has checked the Kraft sum), or have
    # exactly one used symbol, which then decodes from zero bits. *sorted*
    # is scratch space of at least *used* entries.
    def self.build_from_list(symbols : Slice(UInt16), lengths : Slice(UInt8), used : Int32,
                             count : StaticArray(Int32, 16), store : Store, sorted : Slice(UInt16)) : Int32
      start = store.append(ROOT_SIZE)
      if used <= 1
        entry = used == 1 ? symbols[0].to_u32 << 8 : 0_u32
        table = store.to_unsafe + start
        ROOT_SIZE.times { |index| table[index] = entry }
        return start
      end

      # Symbols sorted by code length, then by value: canonical order.
      offsets = StaticArray(Int32, 16).new(0)
      (2..MAX_LENGTH).each { |length| offsets[length] = offsets[length - 1] + count[length - 1] }
      used.times do |index|
        symbol = symbols.unsafe_fetch(index)
        length = lengths.unsafe_fetch(symbol.to_i32)
        sorted[offsets[length]] = symbol
        offsets[length] += 1
      end

      at = 0
      code = 0
      max_length = 0
      # Codes of at most ROOT_BITS bits fill the root directly.
      (1..ROOT_BITS).each do |length|
        step = 1 << length
        count[length].times do
          entry = (sorted[at].to_u32 << 8) | length.to_u32
          index = reverse(code, length)
          table = store.to_unsafe + start
          while index < ROOT_SIZE
            table[index] = entry
            index += step
          end
          at += 1
          code += 1
        end
        code <<= 1
      end

      # Longer codes go to second-level tables, one per root index; codes
      # sharing their first ROOT_BITS bits are contiguous in canonical
      # order.
      low = -1
      sub_start = 0
      sub_size = 0
      (ROOT_BITS + 1..MAX_LENGTH).each do |length|
        step = 1 << (length - ROOT_BITS)
        while count[length] > 0
          reversed = reverse(code, length)
          root = reversed & (ROOT_SIZE - 1)
          if root != low
            width = next_table_bits(count, length)
            sub_size = 1 << width
            sub_start = store.append(sub_size)
            low = root
            (store.to_unsafe + start)[root] = ((sub_start - start).to_u32 << 8) | (ROOT_BITS + width).to_u32
          end
          entry = (sorted[at].to_u32 << 8) | (length - ROOT_BITS).to_u32
          index = reversed >> ROOT_BITS
          table = store.to_unsafe + sub_start
          while index < sub_size
            table[index] = entry
            index += step
          end
          at += 1
          code += 1
          count[length] -= 1
        end
        code <<= 1
      end
      start
    end

    # The index width of the second-level table that starts with a code of
    # *length* bits, from the codes still to place (zlib's method).
    private def self.next_table_bits(count : StaticArray(Int32, 16), length : Int32) : Int32
      left = 1 << (length - ROOT_BITS)
      while length < MAX_LENGTH
        left -= count[length]
        break if left <= 0
        length += 1
        left <<= 1
      end
      length - ROOT_BITS
    end

    # Reverses the low *width* (at most 15) bits of *code*.
    @[AlwaysInline]
    def self.reverse(code : Int32, width : Int32) : Int32
      (code.to_u32.bit_reverse >> (32 - width)).to_i32
    end
  end
end
