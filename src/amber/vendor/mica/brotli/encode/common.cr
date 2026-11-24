# The encoder pipeline of qualities 5 to 11 is a port of google/brotli
# 1.2.1's libbrotlienc (MIT license, copyright the Brotli Authors; the
# license text is in LICENSE.google-brotli next to this file): the same
# hashers, backward reference search, optimal parse, block splitting,
# clustering and bit stream layout, written for Crystal over a flat input
# buffer instead of a ring buffer.
module Amber::Mica::Brotli::Encode
  NUM_DISTANCE_SHORT_CODES =  16
  NUM_LITERAL_SYMBOLS      = 256
  NUM_COMMAND_SYMBOLS      = 704
  NUM_BLOCK_LENGTH_SYMBOLS =  26
  NUM_HISTOGRAM_DISTANCES  = 544
  MAX_BLOCK_TYPES          = 256
  LITERAL_CONTEXT_BITS     =   6
  DISTANCE_CONTEXT_BITS    =   2
  CODE_LENGTH_CODES        =  18
  REPEAT_PREVIOUS_LENGTH   =  16
  REPEAT_ZERO_LENGTH       =  17
  INITIAL_REPEATED_LENGTH  =   8
  MAX_NPOSTFIX             =   3
  MAX_NDIRECT              = 120
  MAX_DISTANCE_BITS        =  24
  WINDOW_GAP               =  16
  CONTEXT_UTF8             =   2
  CONTEXT_SIGNED           =   3

  INSERT_BASE = StaticArray[0_u32, 1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 8_u32, 10_u32, 14_u32, 18_u32, 26_u32,
    34_u32, 50_u32, 66_u32, 98_u32, 130_u32, 194_u32, 322_u32, 578_u32, 1090_u32, 2114_u32, 6210_u32, 22594_u32]
  INSERT_EXTRA = StaticArray[0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 1_u32, 1_u32, 2_u32, 2_u32, 3_u32, 3_u32,
    4_u32, 4_u32, 5_u32, 5_u32, 6_u32, 7_u32, 8_u32, 9_u32, 10_u32, 12_u32, 14_u32, 24_u32]
  COPY_BASE = StaticArray[2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32, 9_u32, 10_u32, 12_u32, 14_u32, 18_u32,
    22_u32, 30_u32, 38_u32, 54_u32, 70_u32, 102_u32, 134_u32, 198_u32, 326_u32, 582_u32, 1094_u32, 2118_u32]
  COPY_EXTRA = StaticArray[0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 1_u32, 1_u32, 2_u32, 2_u32,
    3_u32, 3_u32, 4_u32, 4_u32, 5_u32, 5_u32, 6_u32, 7_u32, 8_u32, 9_u32, 10_u32, 24_u32]

  # Block length prefix codes: the first length of each and its extra bits.
  BLOCK_LENGTH_OFFSET = StaticArray[1_u32, 5_u32, 9_u32, 13_u32, 17_u32, 25_u32, 33_u32, 41_u32, 49_u32, 65_u32,
    81_u32, 97_u32, 113_u32, 145_u32, 177_u32, 209_u32, 241_u32, 305_u32, 369_u32, 497_u32, 753_u32, 1265_u32,
    2289_u32, 4337_u32, 8433_u32, 16625_u32]
  BLOCK_LENGTH_NBITS = StaticArray[2_u32, 2_u32, 2_u32, 2_u32, 3_u32, 3_u32, 3_u32, 3_u32, 4_u32, 4_u32, 4_u32, 4_u32,
    5_u32, 5_u32, 5_u32, 5_u32, 6_u32, 6_u32, 7_u32, 8_u32, 9_u32, 10_u32, 11_u32, 12_u32, 13_u32, 24_u32]

  # log2 of 0 to 255 at float precision (google/brotli's kBrotliLog2Table
  # holds float literals), with log2(0) = 0.
  LOG2_TABLE = begin
    table = StaticArray(Float64, 256).new(0.0)
    (1...256).each { |value| table[value] = Math.log2(value.to_f64).to_f32.to_f64 }
    table
  end

  @[AlwaysInline]
  def self.fast_log2(value : Int) : Float64
    value < 256 ? LOG2_TABLE.unsafe_fetch(value) : Math.log2(value.to_f64)
  end

  @[AlwaysInline]
  def self.log2_floor(value : UInt32) : UInt32
    31_u32 &- value.leading_zeros_count.to_u32
  end

  @[AlwaysInline]
  def self.log2_floor(value : UInt64) : UInt32
    63_u32 &- value.leading_zeros_count.to_u32
  end

  @[AlwaysInline]
  def self.insert_length_code(length : UInt32) : UInt32
    if length < 6
      length
    elsif length < 130
      bits = log2_floor(length &- 2) &- 1
      (bits << 1) &+ ((length &- 2) >> bits) &+ 2
    elsif length < 2114
      log2_floor(length &- 66) &+ 10
    elsif length < 6210
      21_u32
    elsif length < 22594
      22_u32
    else
      23_u32
    end
  end

  @[AlwaysInline]
  def self.copy_length_code(length : UInt32) : UInt32
    if length < 10
      length &- 2
    elsif length < 134
      bits = log2_floor(length &- 6) &- 1
      (bits << 1) &+ ((length &- 6) >> bits) &+ 4
    elsif length < 2118
      log2_floor(length &- 70) &+ 12
    else
      23_u32
    end
  end

  @[AlwaysInline]
  def self.combine_length_codes(insert_code : UInt32, copy_code : UInt32, use_last_distance : Bool) : UInt16
    bits64 = (copy_code & 7) | ((insert_code & 7) << 3)
    if use_last_distance && insert_code < 8 && copy_code < 16
      (copy_code < 8 ? bits64 : bits64 | 64).to_u16!
    else
      offset = 2_u32 &* ((copy_code >> 3) &+ 3_u32 &* (insert_code >> 3))
      offset = (offset << 5) &+ 0x40 &+ ((0x520D40_u32 >> offset) & 0xC0)
      (offset | bits64).to_u16!
    end
  end

  @[AlwaysInline]
  def self.length_code(insert : UInt32, copy : UInt32, use_last_distance : Bool) : UInt16
    combine_length_codes(insert_length_code(insert), copy_length_code(copy), use_last_distance)
  end

  # The distance prefix (code in the low 10 bits, extra bit count above)
  # and extra bits of *distance_code* (a short code, or the distance plus
  # 15) for NPOSTFIX *postfix_bits* and NDIRECT *direct_codes*.
  @[AlwaysInline]
  def self.prefix_encode_distance(distance_code : UInt32, direct_codes : UInt32, postfix_bits : UInt32) : {UInt16, UInt32}
    if distance_code < NUM_DISTANCE_SHORT_CODES &+ direct_codes
      return {distance_code.to_u16!, 0_u32}
    end
    dist = (1_u32 << (postfix_bits &+ 2)) &+ (distance_code &- NUM_DISTANCE_SHORT_CODES &- direct_codes)
    bucket = log2_floor(dist) &- 1
    postfix_mask = (1_u32 << postfix_bits) &- 1
    postfix = dist & postfix_mask
    prefix = (dist >> bucket) & 1
    offset = (2_u32 &+ prefix) << bucket
    nbits = bucket &- postfix_bits
    code = (nbits << 10) | (NUM_DISTANCE_SHORT_CODES &+ direct_codes &+ ((2_u32 &* (nbits &- 1) &+ prefix) << postfix_bits) &+ postfix)
    {code.to_u16!, (dist &- offset) >> postfix_bits}
  end

  @[AlwaysInline]
  def self.block_length_prefix_code(length : UInt32) : Int32
    code = length >= 177 ? (length >= 753 ? 20 : 14) : (length >= 41 ? 7 : 0)
    while code < NUM_BLOCK_LENGTH_SYMBOLS - 1 && length >= BLOCK_LENGTH_OFFSET.unsafe_fetch(code + 1)
      code += 1
    end
    code
  end

  # NPOSTFIX, NDIRECT and what they imply (google/brotli's
  # BrotliDistanceParams, without the large window).
  record DistanceParams, postfix_bits : UInt32, direct_codes : UInt32,
    alphabet_size : UInt32, max_distance : UInt32 do
    def self.new(postfix_bits : UInt32, direct_codes : UInt32) : DistanceParams
      alphabet = NUM_DISTANCE_SHORT_CODES.to_u32 &+ direct_codes &+ (MAX_DISTANCE_BITS.to_u32 << (postfix_bits &+ 1))
      max_distance = direct_codes &+ (1_u32 << (MAX_DISTANCE_BITS &+ postfix_bits &+ 2)) &- (1_u32 << (postfix_bits &+ 2))
      new(postfix_bits, direct_codes, alphabet, max_distance)
    end
  end

  # One insert-and-copy command, laid out like google/brotli's Command:
  # *copy_field* holds the copy length in its low 25 bits and the copy
  # length code minus the copy length in its high 7 (dictionary words
  # cut short), *distance_prefix* the distance code in its low 10 bits
  # and the extra bit count above.
  struct Command
    getter insert_length : UInt32
    getter copy_field : UInt32
    property distance_extra : UInt32
    property command_prefix : UInt16
    property distance_prefix : UInt16

    def initialize(@insert_length, @copy_field, @distance_extra, @command_prefix, @distance_prefix)
    end

    # A command of *insert* literals and a copy of *copy* bytes whose
    # length code is `copy + copy_delta`, at *distance_code*.
    @[AlwaysInline]
    def self.copy(insert : UInt32, copy : UInt32, copy_delta : Int32, distance_code : UInt32, params : DistanceParams) : Command
      delta = (copy_delta.to_i8!.to_u8!).to_u32
      prefix, extra = Encode.prefix_encode_distance(distance_code, params.direct_codes, params.postfix_bits)
      symbol = Encode.length_code(insert, (copy.to_i32 &+ copy_delta).to_u32!, prefix & 0x3FF == 0)
      new(insert, copy | (delta << 25), extra, symbol, prefix)
    end

    # The insert-only command that ends a metablock.
    def self.insert_only(insert : UInt32) : Command
      new(insert, 4_u32 << 25, 0_u32, Encode.length_code(insert, 4_u32, false), NUM_DISTANCE_SHORT_CODES.to_u16)
    end

    @[AlwaysInline]
    def copy_length : UInt32
      @copy_field & 0x1FFFFFF
    end

    @[AlwaysInline]
    def copy_length_code : UInt32
      modifier = @copy_field >> 25
      delta = (modifier | ((modifier & 0x40) << 1)).to_u8!.to_i8!.to_i32
      ((@copy_field & 0x1FFFFFF).to_i32 &+ delta).to_u32!
    end

    @[AlwaysInline]
    def distance_context : UInt32
      row = @command_prefix.to_u32 >> 6
      column = @command_prefix.to_u32 & 7
      (row == 0 || row == 2 || row == 4 || row == 7) && column <= 2 ? column : 3_u32
    end

    # The distance code (short code, or distance plus 15) under *params*.
    def restore_distance_code(params : DistanceParams) : UInt32
      code = @distance_prefix.to_u32 & 0x3FF
      return code if code < NUM_DISTANCE_SHORT_CODES &+ params.direct_codes
      nbits = @distance_prefix.to_u32 >> 10
      postfix_mask = (1_u32 << params.postfix_bits) &- 1
      hcode = (code &- params.direct_codes &- NUM_DISTANCE_SHORT_CODES) >> params.postfix_bits
      lcode = (code &- params.direct_codes &- NUM_DISTANCE_SHORT_CODES) & postfix_mask
      offset = ((2_u32 &+ (hcode & 1)) << nbits) &- 4
      ((offset &+ @distance_extra) << params.postfix_bits) &+ lcode &+ params.direct_codes &+ NUM_DISTANCE_SHORT_CODES
    end

    def with_copy_field(copy_field : UInt32) : Command
      Command.new(@insert_length, copy_field, @distance_extra, @command_prefix, @distance_prefix)
    end

    def with_distance(prefix : UInt16, extra : UInt32) : Command
      Command.new(@insert_length, @copy_field, extra, @command_prefix, prefix)
    end
  end

  # A growable list of commands kept as a raw buffer, so the hot loops
  # write through a pointer.
  class CommandBuffer
    getter size = 0
    @capacity : Int32
    @buffer : Pointer(Command)

    # The buffer lives outside the garbage collector, like the hash
    # tables: it can reach megabytes and holds no references.
    def initialize(capacity : Int32 = 256)
      @capacity = Math.max(capacity, 16)
      @buffer = Encode.table(Command, @capacity)
    end

    def finalize
      @buffer = Encode.free_table(@buffer)
    end

    def reserve(extra : Int32) : Nil
      needed = @size + extra
      return if needed <= @capacity
      capacity = Math.max(needed, @capacity * 2)
      grown = Encode.table(Command, capacity)
      grown.copy_from(@buffer, @size)
      Encode.free_table(@buffer)
      @buffer = grown
      @capacity = capacity
    end

    @[AlwaysInline]
    def push(command : Command) : Nil
      reserve(1) if @size == @capacity
      @buffer[@size] = command
      @size &+= 1
    end

    @[AlwaysInline]
    def [](index : Int32) : Command
      @buffer[index]
    end

    @[AlwaysInline]
    def []=(index : Int32, command : Command) : Command
      @buffer[index] = command
    end

    def to_unsafe : Pointer(Command)
      @buffer
    end

    def clear : Nil
      @size = 0
    end

    # Drops the commands after the first *size*.
    def truncate(size : Int32) : Nil
      @size = size if size < @size
    end

    def last : Command
      @buffer[@size - 1]
    end
  end

  # Shannon bits of `population[0, size]`, at least one per symbol
  # (google/brotli's BrotliBitsEntropy).
  def self.bits_entropy(population : Pointer(UInt32), size : Int32) : Float64
    sum = 0_u64
    result = 0.0
    size.times do |index|
      count = population[index]
      sum &+= count
      result -= count.to_f64 * fast_log2(count)
    end
    result += sum.to_f64 * fast_log2(sum) if sum != 0
    result < sum.to_f64 ? sum.to_f64 : result
  end

  # Shannon entropy of `population[0, size]` (google/brotli's
  # EstimateEntropy in encode.c).
  def self.estimate_entropy(population : Pointer(UInt32), size : Int32) : Float64
    total = 0_u64
    result = 0.0
    size.times do |index|
      count = population[index]
      total &+= count
      result += count.to_f64 * fast_log2(count)
    end
    total.to_f64 * fast_log2(total) - result
  end
end
