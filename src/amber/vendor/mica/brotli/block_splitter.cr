module Amber::Mica::Brotli
  # Splits one symbol category (literals, commands or distances) of a
  # metablock into typed blocks as symbols arrive, the greedy way
  # google/brotli does from quality 5: every block of at least
  # *min_block* symbols starts a new block type when that saves more than
  # *threshold* bits against both of the last two types, joins the second
  # last type when that is clearly cheaper, and otherwise extends the
  # last block. Each type keeps one histogram per context (literal
  # clusters), so the histograms come out ready for the prefix codes.
  #
  # :nodoc:
  class BlockSplitter
    getter types = [] of Int32
    getter lengths = [] of Int32
    getter histograms = [] of Slice(UInt32)
    getter type_count = 0

    @current : Array(Slice(UInt32))
    @block_size = 0
    @target : Int32
    @last = StaticArray(Int32, 2).new(0)
    @last_cost = StaticArray(Float64, 2).new(0.0)
    @merges = 0

    def initialize(@alphabet : Int32, @contexts : Int32, @min_block : Int32, @threshold : Float64, @max_types : Int32)
      @target = @min_block
      @current = Array.new(@contexts) { Slice(UInt32).new(@alphabet, 0_u32) }
    end

    @[AlwaysInline]
    def add(symbol : Int32, context : Int32 = 0) : Nil
      @current.unsafe_fetch(context)[symbol] += 1
      @block_size += 1
      finish_block(false) if @block_size == @target
    end

    def finish : Nil
      finish_block(true)
    end

    # The histogram of type *type* and context *context*.
    def histogram(type : Int32, context : Int32) : Slice(UInt32)
      @histograms[type * @contexts + context]
    end

    private def finish_block(is_final : Bool) : Nil
      if @lengths.empty?
        @lengths << @block_size
        @types << 0
        store_type(@current)
        @type_count = 1
        @last_cost[0] = cost(@current)
        @last_cost[1] = @last_cost[0]
        reset_current
      elsif @block_size > 0
        entropy = cost(@current)
        combined = StaticArray(Array(Slice(UInt32)), 2).new { |slot| combine(@current, @last[slot]) }
        combined_cost = StaticArray(Float64, 2).new { |slot| cost(combined[slot]) }
        difference = StaticArray(Float64, 2).new { |slot| combined_cost[slot] - entropy - @last_cost[slot] }
        if @type_count < @max_types && difference[0] > @threshold && difference[1] > @threshold
          @lengths << @block_size
          @types << @type_count
          @last[1] = @last[0]
          @last[0] = @type_count
          @last_cost[1] = @last_cost[0]
          @last_cost[0] = entropy
          store_type(@current)
          @type_count += 1
          @merges = 0
          @target = @min_block
        elsif difference[1] < difference[0] - 20.0
          @lengths << @block_size
          @types << @types[-2]
          @last[0], @last[1] = @last[1], @last[0]
          replace_type(@last[0], combined[1])
          @last_cost[1] = @last_cost[0]
          @last_cost[0] = combined_cost[1]
          @merges = 0
          @target = @min_block
        else
          @lengths[-1] += @block_size
          replace_type(@last[0], combined[0])
          @last_cost[0] = combined_cost[0]
          @last_cost[1] = @last_cost[0] if @type_count == 1
          @merges += 1
          @target += @min_block if @merges > 1
        end
        reset_current
      end
    end

    private def store_type(source : Array(Slice(UInt32))) : Nil
      source.each { |histogram| @histograms << histogram.dup }
    end

    private def replace_type(type : Int32, source : Array(Slice(UInt32))) : Nil
      @contexts.times { |context| @histograms[type * @contexts + context] = source[context] }
    end

    private def reset_current : Nil
      @current.each { |histogram| histogram.fill(0_u32) }
      @block_size = 0
    end

    private def combine(source : Array(Slice(UInt32)), type : Int32) : Array(Slice(UInt32))
      Array.new(@contexts) do |context|
        mine = source[context]
        theirs = @histograms[type * @contexts + context]
        Slice(UInt32).new(@alphabet) { |symbol| mine[symbol] + theirs[symbol] }
      end
    end

    private def cost(histograms : Array(Slice(UInt32))) : Float64
      histograms.sum { |histogram| Entropy.bits(histogram) }
    end
  end

  # Entropy estimates shared by the encoder's modeling decisions.
  #
  # :nodoc:
  module Entropy
    LOG2 = Array(Float64).new(256) { |value| value == 0 ? 0.0 : Math.log2(value) }

    @[AlwaysInline]
    def self.log2(value : UInt32 | Int32 | Int64) : Float64
      value < 256 ? LOG2.unsafe_fetch(value) : Math.log2(value)
    end

    # Shannon bits of *histogram*, at least one bit per symbol (google/
    # brotli's BitsEntropy).
    def self.bits(histogram : Slice(UInt32)) : Float64
      total = 0_i64
      sum = 0.0
      histogram.each do |count|
        next if count == 0
        total += count
        sum -= count * log2(count)
      end
      return 0.0 if total == 0
      sum += total * log2(total)
      Math.max(sum, total.to_f64)
    end

    # Shannon bits plus an estimate of the prefix code header.
    def self.population_cost(histogram : Slice(UInt32)) : Float64
      used = histogram.count { |count| count > 0 }
      return 12.0 if used <= 1
      bits = 0.0
      total = 0_i64
      histogram.each do |count|
        next if count == 0
        total += count
        bits -= count * log2(count)
      end
      bits += total * log2(total)
      bits + (used <= 4 ? 10.0 + used * 8 : 30.0 + used * 3.5)
    end
  end
end
