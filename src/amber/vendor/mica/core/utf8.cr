module Amber::Mica::Core
  # UTF-8 decoding and encoding (RFC 3629), shared by every text format.
  #
  # Decoding is strict: overlong forms, encoded surrogates (U+D800 to
  # U+DFFF), code points above U+10FFFF, the retired 5- and 6-byte forms
  # (lead bytes F8 to FD), FE and FF, stray continuation bytes and
  # truncated sequences are all rejected. Nothing is ever replaced with
  # U+FFFD.
  module UTF8
    # Why a sequence failed to decode, from `decode`.
    enum Problem
      # Fewer bytes are available than the lead byte announces.
      Truncated
      # A continuation byte (80 to BF) where a lead byte belongs.
      UnexpectedContinuation
      # A lead byte C0 or C1, or a longer sequence that encodes a code
      # point a shorter one could.
      Overlong
      # A 3-byte sequence encoding U+D800 to U+DFFF.
      Surrogate
      # A 4-byte sequence above U+10FFFF (lead bytes F4 with a high
      # second byte, F5 to F7).
      OutOfRange
      # A 5- or 6-byte lead byte (F8 to FD), or FE or FF.
      InvalidLeadByte
      # A lead byte followed by a byte that is not a continuation byte.
      BadContinuation

      def describe : String
        case self
        in .truncated?               then "truncated UTF-8 sequence"
        in .unexpected_continuation? then "UTF-8 continuation byte without a lead byte"
        in .overlong?                then "overlong UTF-8 encoding"
        in .surrogate?               then "UTF-8 encoding of a UTF-16 surrogate"
        in .out_of_range?            then "UTF-8 sequence above U+10FFFF"
        in .invalid_lead_byte?       then "byte that never appears in UTF-8"
        in .bad_continuation?        then "UTF-8 sequence with a missing continuation byte"
        end
      end
    end

    # Returns the number of bytes the sequence led by *lead* occupies:
    # 1 for ASCII and for bytes that cannot lead a sequence.
    @[AlwaysInline]
    def self.sequence_length(lead : UInt8) : Int32
      if lead < 0xC0
        1
      elsif lead < 0xE0
        2
      elsif lead < 0xF0
        3
      else
        4
      end
    end

    # Decodes the sequence at the start of *bytes*. Returns
    # `{code_point, byte_length}`; on failure the length is 0 and the code
    # point is the `Problem` value.
    #
    # ```
    # Amber::Mica::Core::UTF8.decode("é".to_slice)      # => {233, 2}
    # Amber::Mica::Core::UTF8.decode(Bytes[0xC0, 0x80]) # => {2, 0} (Problem::Overlong)
    # ```
    def self.decode(bytes : Bytes) : {Int32, Int32}
      decode(bytes, 0, bytes.size)
    end

    # Decodes the sequence at *offset* in *bytes*, reading no byte at or
    # past *limit* (at most `bytes.size`). Scanners call this form on their
    # hot path with their buffer, position and fill level; every read is
    # bounds-checked.
    def self.decode(bytes : Bytes, offset : Int32, limit : Int32) : {Int32, Int32}
      return {Problem::Truncated.value, 0} if offset >= limit
      b0 = bytes[offset].to_i32
      return {b0, 1} if b0 < 0x80
      return {Problem::UnexpectedContinuation.value, 0} if b0 < 0xC0
      return {Problem::Overlong.value, 0} if b0 < 0xC2
      return {Problem::InvalidLeadByte.value, 0} if b0 >= 0xF8
      length = b0 < 0xE0 ? 2 : (b0 < 0xF0 ? 3 : 4)
      # Report a bad continuation before truncation, so the verdict for a
      # prefix never depends on how many bytes follow it.
      index = 1
      while index < length
        return {Problem::Truncated.value, 0} if offset + index >= limit
        return {Problem::BadContinuation.value, 0} unless bytes[offset + index] & 0xC0 == 0x80
        index += 1
      end
      b1 = bytes[offset + 1].to_i32 & 0x3F
      case length
      when 2
        {((b0 & 0x1F) << 6) | b1, 2}
      when 3
        code = ((b0 & 0x0F) << 12) | (b1 << 6) | (bytes[offset + 2].to_i32 & 0x3F)
        return {Problem::Overlong.value, 0} if code < 0x800
        return {Problem::Surrogate.value, 0} if code >= 0xD800 && code <= 0xDFFF
        {code, 3}
      else
        code = ((b0 & 0x07) << 18) | (b1 << 12) | ((bytes[offset + 2].to_i32 & 0x3F) << 6) | (bytes[offset + 3].to_i32 & 0x3F)
        return {Problem::Overlong.value, 0} if code < 0x10000
        return {Problem::OutOfRange.value, 0} if code > 0x10FFFF
        {code, 4}
      end
    end

    # Returns the problem for a failed `decode` result.
    def self.problem(code : Int32) : Problem
      Problem.from_value(code)
    end

    # Returns the number of bytes `encode` writes for *code*.
    @[AlwaysInline]
    def self.encoded_size(code : Int32) : Int32
      if code < 0x80
        1
      elsif code < 0x800
        2
      elsif code < 0x10000
        3
      else
        4
      end
    end

    # Writes the UTF-8 encoding of *code* (a scalar value) at the start of
    # *target*, which must have room for `encoded_size(code)` bytes. Returns
    # the number of bytes written.
    def self.encode(code : Int32, target : Bytes) : Int32
      size = encoded_size(code)
      raise ArgumentError.new("UTF-8 target too small") if target.size < size
      case size
      when 1
        target[0] = code.to_u8
      when 2
        target[0] = (0xC0 | (code >> 6)).to_u8
        target[1] = (0x80 | (code & 0x3F)).to_u8
      when 3
        target[0] = (0xE0 | (code >> 12)).to_u8
        target[1] = (0x80 | ((code >> 6) & 0x3F)).to_u8
        target[2] = (0x80 | (code & 0x3F)).to_u8
      else
        target[0] = (0xF0 | (code >> 18)).to_u8
        target[1] = (0x80 | ((code >> 12) & 0x3F)).to_u8
        target[2] = (0x80 | ((code >> 6) & 0x3F)).to_u8
        target[3] = (0x80 | (code & 0x3F)).to_u8
      end
      size
    end

    # Returns the offset of the first invalid sequence in *bytes* (its lead
    # byte, as `decode` reports it), or nil when all of it is valid UTF-8.
    #
    # Runs in one pass over valid text: the ASCII prefix 32 bytes at a time
    # (four words tested together), then runs of ASCII sixteen bytes at a
    # time and everything else through the shift DFA below, 64 bytes per
    # step with one table read and one shift per byte. Text past
    # `TWO_STREAM_BYTES` is read as two halves at once, split where a
    # sequence begins: each half's next state waits on its last one (a
    # shift, then a mask), so two independent chains keep the core busy
    # where one leaves it waiting, and text in any script validates at
    # about two bytes per cycle. Only when that pass finds the text invalid
    # does a second pass from the same place (`first_invalid_from`) track
    # where each sequence begins, to report the offset.
    def self.first_invalid_offset(bytes : Bytes) : Int32?
      size = bytes.size
      pointer = bytes.to_unsafe
      return nil if short_ascii?(pointer, size)
      # The ASCII prefix, 32 bytes, then eight, then one at a time: a
      # haystack that is all ASCII (the common case) never reaches the DFA.
      index = 0
      while index + 32 <= size &&
            ((pointer + index).as(UInt64*).value | (pointer + index + 8).as(UInt64*).value |
              (pointer + index + 16).as(UInt64*).value | (pointer + index + 24).as(UInt64*).value) & ASCII_MASK == 0
        index += 32
      end
      while index + 8 <= size && (pointer + index).as(UInt64*).value & ASCII_MASK == 0
        index += 8
      end
      while index < size && pointer[index] < 0x80
        index += 1
      end
      return nil if index == size
      start = index
      if size - start >= TWO_STREAM_BYTES && (middle = sequence_start_near(bytes, start + (size - start) // 2))
        valid = valid_in_two_streams?(pointer, start, middle, size)
      else
        valid = valid_from?(pointer, start, size)
      end
      valid ? nil : first_invalid_from(bytes, start)
    end

    # True when *pointer*[0...size] is ASCII and at most `SHORT_ASCII_BYTES`
    # long, tested with one branch: the words are OR-ed together, the last
    # one read where it ends with the text (overlapping the one before), and
    # text under eight bytes is read as two overlapping four-byte words or
    # byte by byte. A one-line haystack (a grep model's line, a form field)
    # is validated in a few cycles, where the loops below mispredict their
    # exits on every length. False otherwise, also for longer text.
    @[AlwaysInline]
    private def self.short_ascii?(pointer : UInt8*, size : Int32) : Bool
      return false if size > SHORT_ASCII_BYTES
      if size >= 8
        bits = (pointer + size - 8).as(UInt64*).value
        index = 0
        while index + 8 < size
          bits |= (pointer + index).as(UInt64*).value
          index += 8
        end
        bits & ASCII_MASK == 0
      elsif size >= 4
        ((pointer.as(UInt32*).value | (pointer + size - 4).as(UInt32*).value) & 0x80808080_u32) == 0
      else
        bits = 0_u8
        size.times { |at| bits |= pointer[at] }
        bits < 0x80
      end
    end

    # The longest text `short_ascii?` tests.
    private SHORT_ASCII_BYTES = 64

    # Text at least this long past its ASCII prefix is validated as two
    # streams (see `first_invalid_offset`).
    private TWO_STREAM_BYTES = 512

    # The high bit of each byte of a word: a word is ASCII when none is set.
    private ASCII_MASK = 0x8080808080808080_u64

    # The first index at or after *index* (within three bytes) where a
    # sequence may begin (a byte that is not a continuation byte), or nil.
    # Two halves split there are valid exactly when the whole is: a
    # sequence the first half leaves unfinished meets that byte, which
    # cannot continue it, so the first half ends outside the accept state.
    private def self.sequence_start_near(bytes : Bytes, index : Int32) : Int32?
      stop = Math.min(index + 4, bytes.size)
      while index < stop
        return index if bytes.unsafe_fetch(index) & 0xC0 != 0x80
        index += 1
      end
      nil
    end

    # True when *pointer*[index...stop] is valid UTF-8, read from the
    # accept state through the shift DFA.
    private def self.valid_from?(pointer : UInt8*, index : Int32, stop : Int32) : Bool
      table = VALIDATION_TABLE.to_unsafe
      # The state's shift sits in the low six bits; the bits above are what
      # is left of the row it came from, which the next shift drops.
      state = ACCEPT_SHIFT
      while index + 64 <= stop
        if state & 63 == ACCEPT_SHIFT &&
           ((pointer + index).as(UInt64*).value | (pointer + index + 8).as(UInt64*).value) & ASCII_MASK == 0
          index += 16
          next
        end
        # Text that is not ASCII here likely goes on that way: 64 bytes
        # through the DFA before the next ASCII check.
        # One word load per eight bytes, each byte taken from it by a
        # shift (the word is little-endian, as on every target Mica builds
        # for; see `Prefilter.word_at`): a load per byte for the table row
        # alone, where a load per byte for the byte too leaves the loads
        # the limit.
        {% for word in 0...8 %}
          word = (pointer + index + {{ word * 8 }}).as(UInt64*).value
          {% for byte in 0...8 %}
            state = table[(word >> {{ byte * 8 }}) & 0xFF].unsafe_shr(state & 63)
          {% end %}
        {% end %}
        return false if state & 63 == ERROR_SHIFT
        index += 64
      end
      while index < stop
        state = table[pointer[index]].unsafe_shr(state & 63)
        index += 1
      end
      state & 63 == ACCEPT_SHIFT
    end

    # True when *pointer*[start...stop] is valid UTF-8, read as the two
    # streams start...middle and middle...stop (*middle* begins a sequence,
    # see `sequence_start_near`), 64 bytes of each per step, interleaved.
    # A stream in its accept state skips ASCII sixteen bytes at a time on
    # its own; the streams step together while each has 64 bytes left, and
    # each finishes alone.
    private def self.valid_in_two_streams?(pointer : UInt8*, start : Int32, middle : Int32, stop : Int32) : Bool
      table = VALIDATION_TABLE.to_unsafe
      first = start
      second = middle
      first_state = ACCEPT_SHIFT
      second_state = ACCEPT_SHIFT
      while true
        while first + 64 <= middle && first_state & 63 == ACCEPT_SHIFT &&
              ((pointer + first).as(UInt64*).value | (pointer + first + 8).as(UInt64*).value) & ASCII_MASK == 0
          first += 16
        end
        while second + 64 <= stop && second_state & 63 == ACCEPT_SHIFT &&
              ((pointer + second).as(UInt64*).value | (pointer + second + 8).as(UInt64*).value) & ASCII_MASK == 0
          second += 16
        end
        break unless first + 64 <= middle && second + 64 <= stop
        {% for word in 0...8 %}
          first_word = (pointer + first + {{ word * 8 }}).as(UInt64*).value
          second_word = (pointer + second + {{ word * 8 }}).as(UInt64*).value
          {% for byte in 0...8 %}
            first_state = table[(first_word >> {{ byte * 8 }}) & 0xFF].unsafe_shr(first_state & 63)
            second_state = table[(second_word >> {{ byte * 8 }}) & 0xFF].unsafe_shr(second_state & 63)
          {% end %}
        {% end %}
        return false if first_state & 63 == ERROR_SHIFT || second_state & 63 == ERROR_SHIFT
        first += 64
        second += 64
      end
      # Each stream's rest, alone, from the state it reached.
      finish_stream?(pointer, table, first, middle, first_state) && finish_stream?(pointer, table, second, stop, second_state)
    end

    # True when the rest of a stream, *pointer*[index...stop] read on from
    # *state*, ends in the accept state.
    private def self.finish_stream?(pointer : UInt8*, table : UInt64*, index : Int32, stop : Int32, state : UInt64) : Bool
      if state & 63 == ACCEPT_SHIFT
        return valid_from?(pointer, index, stop)
      end
      # Finish the sequence in progress byte by byte (at most three bytes),
      # then the rest from the accept state.
      while index < stop && state & 63 != ACCEPT_SHIFT
        state = table[pointer[index]].unsafe_shr(state & 63)
        return false if state & 63 == ERROR_SHIFT
        index += 1
      end
      return false unless state & 63 == ACCEPT_SHIFT
      valid_from?(pointer, index, stop)
    end

    # The offset of the first invalid sequence in *bytes* at or after
    # *index* (where a sequence begins), or nil: the shift DFA one byte at
    # a time, remembering where each sequence begins.
    private def self.first_invalid_from(bytes : Bytes, index : Int32) : Int32?
      size = bytes.size
      pointer = bytes.to_unsafe
      table = VALIDATION_TABLE.to_unsafe
      state = ACCEPT_SHIFT
      lead = index
      while index < size
        lead = index if state == ACCEPT_SHIFT
        state = table[pointer[index]].unsafe_shr(state) & 63
        return lead if state == ERROR_SHIFT
        index += 1
      end
      state == ACCEPT_SHIFT ? nil : lead
    end

    # The states of the validation DFA: the error state, between sequences
    # (accept), and the bytes still owed by the sequence being read, with
    # the four leads whose second byte has a narrower range (E0 rules out
    # overlong forms, ED surrogates, F0 overlong forms, F4 code points
    # above U+10FFFF).
    private enum ValidationState
      Error
      Accept
      OneMore
      TwoMore
      ThreeMore
      AfterE0
      AfterED
      AfterF0
      AfterF4
    end

    # A state is stored as its shift: six bits per state, so the nine fit
    # one 64-bit row.
    private ERROR_SHIFT  = ValidationState::Error.value.to_u64 * 6
    private ACCEPT_SHIFT = ValidationState::Accept.value.to_u64 * 6

    # One row per byte value: for each state, the shift of the state that
    # byte leads to, at bit `6 × state` ("shift DFA": the next state is
    # `(row >> state) & 63`).
    private VALIDATION_TABLE = begin
      table = StaticArray(UInt64, 256).new(0_u64)
      256.times do |byte|
        row = 0_u64
        ValidationState.each do |state|
          row |= (validation_step(state, byte).value.to_u64 * 6) << (state.value * 6)
        end
        table[byte] = row
      end
      table
    end

    # The state after *byte* in *state* (`decode`'s rules).
    private def self.validation_step(state : ValidationState, byte : Int32) : ValidationState
      continuation = 0x80 <= byte <= 0xBF
      case state
      when .accept?
        return ValidationState::Accept if byte < 0x80
        return ValidationState::Error if byte < 0xC2
        return ValidationState::OneMore if byte < 0xE0
        return ValidationState::AfterE0 if byte == 0xE0
        return ValidationState::AfterED if byte == 0xED
        return ValidationState::TwoMore if byte < 0xF0
        return ValidationState::AfterF0 if byte == 0xF0
        return ValidationState::ThreeMore if byte < 0xF4
        return ValidationState::AfterF4 if byte == 0xF4
        ValidationState::Error
      when .one_more?   then continuation ? ValidationState::Accept : ValidationState::Error
      when .two_more?   then continuation ? ValidationState::OneMore : ValidationState::Error
      when .three_more? then continuation ? ValidationState::TwoMore : ValidationState::Error
      when .after_e0?   then 0xA0 <= byte <= 0xBF ? ValidationState::OneMore : ValidationState::Error
      when .after_ed?   then 0x80 <= byte <= 0x9F ? ValidationState::OneMore : ValidationState::Error
      when .after_f0?   then 0x90 <= byte <= 0xBF ? ValidationState::TwoMore : ValidationState::Error
      when .after_f4?   then 0x80 <= byte <= 0x8F ? ValidationState::TwoMore : ValidationState::Error
      else                   ValidationState::Error
      end
    end
  end
end
