module Amber::Mica::Brotli
  # One prefix code of the encoder: its lengths and reversed codes, built
  # from a histogram and stored in the stream as a simple code (1 to 4
  # used symbols) or a complex code with the run-length code length
  # alphabet (RFC 7932, section 3.4 and 3.5).
  #
  # :nodoc:
  class HuffmanCode
    # The order code length code lengths are stored in (RFC 7932, 3.5).
    CODE_LENGTH_ORDER = Decoder::CODE_LENGTH_ORDER

    # The fixed code for code length code lengths 0 to 5: its width and
    # its bits, taken from the decoder's 4-bit peek table so the two
    # cannot disagree.
    CODE_LENGTH_CODE_WIDTH = begin
      widths = StaticArray(Int32, 6).new(0)
      6.times do |value|
        peek = (0...16).find! { |index| Decoder::CODE_LENGTH_PREFIX_VALUE[index] == value }
        widths[value] = Decoder::CODE_LENGTH_PREFIX_BITS[peek]
      end
      widths
    end
    CODE_LENGTH_CODE_BITS = begin
      bits = StaticArray(Int32, 6).new(0)
      6.times do |value|
        peek = (0...16).find! { |index| Decoder::CODE_LENGTH_PREFIX_VALUE[index] == value }
        bits[value] = peek & ((1 << Decoder::CODE_LENGTH_PREFIX_BITS[peek]) - 1)
      end
      bits
    end

    # The repeated length the code length alphabet starts from.
    INITIAL_REPEATED_LENGTH = 8

    getter lengths : Bytes
    getter codes : Slice(UInt16)

    def initialize(capacity : Int32)
      @lengths = Bytes.new(capacity)
      @codes = Slice(UInt16).new(capacity)
    end

    # Writes *symbol*.
    @[AlwaysInline]
    def write(writer : BitWriter, symbol : Int32) : Nil
      writer.write(@lengths.unsafe_fetch(symbol).to_i32, @codes.unsafe_fetch(symbol))
    end

    # Builds the code for `counts[0, alphabet]` and stores it with *writer*.
    def build_and_store(writer : BitWriter, counts : Slice(UInt32), alphabet : Int32) : Nil
      used = 0
      symbols = StaticArray(Int32, 4).new(0)
      alphabet.times do |symbol|
        next if counts[symbol] == 0
        symbols[used] = symbol if used < 4
        used += 1
      end
      if used <= 4
        store_simple(writer, counts, alphabet, symbols, used)
      else
        HuffmanBuilder.build_lengths(counts, alphabet, 15, @lengths)
        HuffmanBuilder.assign_codes(@lengths, alphabet, @codes)
        store_complex(writer, alphabet)
      end
    end

    # The cost in bits of *counts* under this code (after a build).
    def cost(counts : Slice(UInt32), alphabet : Int32) : Int64
      total = 0_i64
      alphabet.times { |symbol| total += counts[symbol].to_i64 * @lengths[symbol] }
      total
    end

    private def store_simple(writer : BitWriter, counts : Slice(UInt32), alphabet : Int32,
                             symbols : StaticArray(Int32, 4), used : Int32) : Nil
      @lengths[0, alphabet].fill(0_u8)
      if used == 0
        used = 1
        symbols[0] = 0
      end
      if used == 1
        @lengths[symbols[0]] = 0_u8
      else
        HuffmanBuilder.build_lengths(counts, alphabet, 3, @lengths)
      end
      # Listed by length, then by symbol: the decoder gives the first
      # listed symbols the shorter lengths.
      listed = symbols.to_slice[0, used].to_a.sort_by! { |symbol| {@lengths[symbol], symbol} }
      tree_select = used == 4 && @lengths[listed[0]] == 1
      if used == 4 && !tree_select
        listed.each { |symbol| @lengths[symbol] = 2_u8 }
      end
      symbol_bits = 0
      while (1 << symbol_bits) < alphabet
        symbol_bits += 1
      end
      writer.write(2, 1)
      writer.write(2, used - 1)
      listed.each { |symbol| writer.write(symbol_bits, symbol) }
      writer.write(1, tree_select ? 1 : 0) if used == 4
      HuffmanBuilder.assign_codes(@lengths, alphabet, @codes)
    end

    private def store_complex(writer : BitWriter, alphabet : Int32) : Nil
      tokens = [] of Int32
      extras = [] of Int32
      tokenize_lengths(alphabet, tokens, extras)
      token_counts = Slice(UInt32).new(18, 0_u32)
      tokens.each { |token| token_counts[token] += 1 }
      used = token_counts.count { |count| count > 0 }
      if used == 1
        # A lone code length symbol would cost 0 bits per token; give it a
        # partner so the code length code is a complete two-symbol code.
        token_counts[tokens[0] == 0 ? 1 : 0] = 1_u32
      end
      length_lengths = Bytes.new(18)
      HuffmanBuilder.build_lengths(token_counts, 18, 5, length_lengths)
      length_codes = Slice(UInt16).new(18)
      HuffmanBuilder.assign_codes(length_lengths, 18, length_codes)

      stored = 18
      while stored > 0 && length_lengths[CODE_LENGTH_ORDER[stored - 1]] == 0
        stored -= 1
      end
      skip = 0
      if length_lengths[CODE_LENGTH_ORDER[0]] == 0 && length_lengths[CODE_LENGTH_ORDER[1]] == 0
        skip = length_lengths[CODE_LENGTH_ORDER[2]] == 0 ? 3 : 2
      end
      writer.write(2, skip)
      (skip...stored).each do |index|
        value = length_lengths[CODE_LENGTH_ORDER[index]].to_i32
        writer.write(CODE_LENGTH_CODE_WIDTH[value], CODE_LENGTH_CODE_BITS[value])
      end
      tokens.each_with_index do |token, index|
        writer.write(length_lengths[token].to_i32, length_codes[token])
        if token == 16
          writer.write(2, extras[index])
        elsif token == 17
          writer.write(3, extras[index])
        end
      end
    end

    # Turns the code lengths into code length symbols with the repeat
    # codes 16 (previous length) and 17 (zeros), as google/brotli does.
    private def tokenize_lengths(alphabet : Int32, tokens : Array(Int32), extras : Array(Int32)) : Nil
      length = alphabet
      while length > 0 && @lengths[length - 1] == 0
        length -= 1
      end
      use_zero_runs, use_length_runs = decide_runs(length)
      previous = INITIAL_REPEATED_LENGTH
      index = 0
      while index < length
        value = @lengths[index].to_i32
        repeats = 1
        while index + repeats < length && @lengths[index + repeats] == value
          repeats += 1
        end
        if value == 0 && use_zero_runs
          zero_run(repeats, tokens, extras)
        elsif value != 0 && use_length_runs
          length_run(previous, value, repeats, tokens, extras)
          previous = value
        else
          repeats.times do
            tokens << value
            extras << 0
          end
          previous = value if value != 0
        end
        index += repeats
      end
    end

    private def decide_runs(length : Int32) : {Bool, Bool}
      return {false, false} if length <= 50
      zero_total = 0
      zero_runs = 1
      other_total = 0
      other_runs = 1
      index = 0
      while index < length
        value = @lengths[index]
        repeats = 1
        while index + repeats < length && @lengths[index + repeats] == value
          repeats += 1
        end
        if value == 0 && repeats >= 3
          zero_total += repeats
          zero_runs += 1
        elsif value != 0 && repeats >= 4
          other_total += repeats
          other_runs += 1
        end
        index += repeats
      end
      {zero_total > zero_runs * 2, other_total > other_runs * 2}
    end

    private def length_run(previous : Int32, value : Int32, repeats : Int32, tokens : Array(Int32), extras : Array(Int32)) : Nil
      if previous != value
        tokens << value
        extras << 0
        repeats -= 1
      end
      if repeats == 7
        tokens << value
        extras << 0
        repeats -= 1
      end
      if repeats < 3
        repeats.times do
          tokens << value
          extras << 0
        end
        return
      end
      repeat_run(16, 2, repeats - 3, tokens, extras)
    end

    private def zero_run(repeats : Int32, tokens : Array(Int32), extras : Array(Int32)) : Nil
      if repeats == 11
        tokens << 0
        extras << 0
        repeats -= 1
      end
      if repeats < 3
        repeats.times do
          tokens << 0
          extras << 0
        end
        return
      end
      repeat_run(17, 3, repeats - 3, tokens, extras)
    end

    # Writes *rest* (the run length less 3) as repeat codes, most
    # significant digit first: each further repeat code multiplies the
    # run so far by 4 (code 16) or 8 (code 17).
    private def repeat_run(code : Int32, width : Int32, rest : Int32, tokens : Array(Int32), extras : Array(Int32)) : Nil
      start = tokens.size
      mask = (1 << width) - 1
      loop do
        tokens << code
        extras << (rest & mask)
        rest >>= width
        break if rest == 0
        rest -= 1
      end
      tokens[start..] = tokens[start..].reverse
      extras[start..] = extras[start..].reverse
    end
  end
end
