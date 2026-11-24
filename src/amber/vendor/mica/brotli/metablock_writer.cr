module Amber::Mica::Brotli
  # One command of a metablock: *insert* literals, then a copy of
  # *output* bytes (0 for the insert-only command that ends a
  # metablock). *copy* is the copy length the command code carries (a
  # dictionary word's length, which can exceed *output*). *distance_code*
  # is the distance symbol, or -1 when no distance is written; *symbol* is
  # the insert-and-copy symbol.
  #
  # :nodoc:
  record Command, insert : Int32, copy : Int32, output : Int32, symbol : Int32,
    distance_code : Int32, distance_extra_bits : Int32, distance_extra : Int32

  # Writes a compressed metablock (RFC 7932, section 9.2 and 9.3) for a
  # list of commands: chooses the literal context mode and clusters,
  # splits each category into block types, builds the prefix codes, and
  # writes the header, the codes and the commands.
  #
  # :nodoc:
  class MetablockWriter
    LITERAL_ALPHABET  = 256
    COMMAND_ALPHABET  = 704
    DISTANCE_ALPHABET =  64
    BLOCK_COUNT_CODES =  26
    MODE_LSB6         =   0
    MODE_UTF8         =   2
    MODE_SIGNED       =   3
    MAX_CLUSTERS      =  16

    # Splitting parameters per category: minimum block, split threshold
    # in bits (google/brotli's greedy splitter values).
    LITERAL_SPLIT  = {512, 400.0}
    COMMAND_SPLIT  = {1024, 500.0}
    DISTANCE_SPLIT = {512, 100.0}

    def initialize(@quality : Int32)
      @scratch_code = HuffmanCode.new(COMMAND_ALPHABET)
    end

    # Writes the metablock holding `input[start, length]` as *commands*.
    def write(writer : BitWriter, input : Bytes, start : Int32, length : Int32,
              commands : Array(Command), is_last : Bool) : Nil
      write_header(writer, length, is_last)
      mode, cluster_map, clusters = choose_literal_model(input, start, commands)
      split = @quality >= 5
      literal = splitter(LITERAL_ALPHABET, clusters, LITERAL_SPLIT, split ? 256 // clusters : 1)
      command = splitter(COMMAND_ALPHABET, 1, COMMAND_SPLIT, split ? 256 : 1)
      distance = splitter(DISTANCE_ALPHABET, 1, DISTANCE_SPLIT, split ? 256 : 1)
      lookup = Tables::CONTEXT_LOOKUP.to_unsafe + mode * 512
      position = start
      commands.each do |entry|
        command.add(entry.symbol)
        entry.insert.times do
          literal.add(input[position].to_i32, cluster_map[context_at(input, position, lookup)].to_i32)
          position += 1
        end
        distance.add(entry.distance_code) if entry.distance_code >= 0
        position += entry.output
      end
      {literal, command, distance}.each(&.finish)

      categories = {literal, command, distance}
      switches = categories.map { |category| BlockSwitchWriter.new(category) }
      switches.each(&.store_header(writer))
      writer.write(2, 0) # NPOSTFIX
      writer.write(4, 0) # NDIRECT >> NPOSTFIX
      literal.type_count.times { writer.write(2, mode) }

      literal_trees = literal.type_count * clusters
      literal_map = Bytes.new(literal.type_count * 64) do |slot|
        ((slot >> 6) * clusters + cluster_map[slot & 63]).to_u8
      end
      write_var_len(writer, literal_trees - 1)
      store_context_map(writer, literal_map, literal_trees) if literal_trees > 1
      distance_map = Bytes.new(distance.type_count * 4) { |slot| (slot >> 2).to_u8 }
      write_var_len(writer, distance.type_count - 1)
      store_context_map(writer, distance_map, distance.type_count) if distance.type_count > 1

      literal_codes = Array.new(literal_trees) { HuffmanCode.new(LITERAL_ALPHABET) }
      literal_codes.each_with_index { |code, tree| code.build_and_store(writer, literal.histograms[tree], LITERAL_ALPHABET) }
      command_codes = Array.new(command.type_count) { HuffmanCode.new(COMMAND_ALPHABET) }
      command_codes.each_with_index { |code, type| code.build_and_store(writer, command.histograms[type], COMMAND_ALPHABET) }
      distance_codes = Array.new(distance.type_count) { HuffmanCode.new(DISTANCE_ALPHABET) }
      distance_codes.each_with_index { |code, type| code.build_and_store(writer, distance.histograms[type], DISTANCE_ALPHABET) }

      literal_switch, command_switch, distance_switch = switches
      position = start
      commands.each do |entry|
        command_code = command_codes.unsafe_fetch(command_switch.next_type(writer))
        command_code.write(writer, entry.symbol)
        insert_code = EncoderCodes.insert_code(entry.insert)
        writer.write(Decoder::INSERT_EXTRA[insert_code], entry.insert - Decoder::INSERT_BASE[insert_code])
        copy_code = EncoderCodes.copy_code(entry.copy)
        writer.write(Decoder::COPY_EXTRA[copy_code], entry.copy - Decoder::COPY_BASE[copy_code])
        entry.insert.times do
          type = literal_switch.next_type(writer)
          tree = type * clusters + cluster_map[context_at(input, position, lookup)]
          literal_codes.unsafe_fetch(tree).write(writer, input[position].to_i32)
          position += 1
        end
        if entry.distance_code >= 0
          distance_codes.unsafe_fetch(distance_switch.next_type(writer)).write(writer, entry.distance_code)
          writer.write(entry.distance_extra_bits, entry.distance_extra)
        end
        position += entry.output
      end
    end

    # The literal context of `input[position]` from the two bytes before
    # it (0 before the stream's start).
    @[AlwaysInline]
    private def context_at(input : Bytes, position : Int32, lookup : UInt8*) : Int32
      previous = position >= 1 ? input.unsafe_fetch(position - 1) : 0_u8
      before = position >= 2 ? input.unsafe_fetch(position - 2) : 0_u8
      (lookup[previous] | lookup[256 + before]).to_i32
    end

    private def splitter(alphabet : Int32, contexts : Int32, parameters : {Int32, Float64}, max_types : Int32) : BlockSplitter
      BlockSplitter.new(alphabet, contexts, parameters[0], parameters[1], max_types)
    end

    private def write_header(writer : BitWriter, length : Int32, is_last : Bool) : Nil
      writer.write(1, is_last ? 1 : 0)
      writer.write(1, 0) if is_last # ISLASTEMPTY
      nibbles = EncoderCodes.length_nibbles(length)
      writer.write(2, nibbles - 4)
      writer.write(nibbles * 4, length - 1)
      writer.write(1, 0) unless is_last # ISUNCOMPRESSED
    end

    def write_var_len(writer : BitWriter, value : Int32) : Nil
      if value == 0
        writer.write(1, 0)
        return
      end
      bits = MatchFinder.log2_floor(value)
      writer.write(1, 1)
      writer.write(3, bits)
      writer.write(bits, value - (1 << bits))
    end

    # Chooses the literal context mode and a map from its 64 contexts to
    # at most MAX_CLUSTERS clusters by an entropy estimate; below quality
    # 5, one cluster.
    private def choose_literal_model(input : Bytes, start : Int32, commands : Array(Command)) : {Int32, Bytes, Int32}
      single = Bytes.new(64, 0_u8)
      literal_count = commands.sum(0_i64) { |entry| entry.insert.to_i64 }
      # Few literals cannot pay for extra prefix codes.
      return {MODE_LSB6, single, 1} if @quality < 5 || literal_count < 1024
      best = {MODE_LSB6, single, 1}
      best_cost = Float64::MAX
      {MODE_UTF8, MODE_SIGNED}.each do |mode|
        histograms = Array.new(64) { Slice(UInt32).new(LITERAL_ALPHABET, 0_u32) }
        lookup = Tables::CONTEXT_LOOKUP.to_unsafe + mode * 512
        position = start
        commands.each do |entry|
          entry.insert.times do
            histograms[context_at(input, position, lookup)][input[position]] += 1
            position += 1
          end
          position += entry.output
        end
        if best_cost == Float64::MAX
          whole = Slice(UInt32).new(LITERAL_ALPHABET, 0_u32)
          histograms.each { |histogram| LITERAL_ALPHABET.times { |symbol| whole[symbol] += histogram[symbol] } }
          best_cost = Entropy.population_cost(whole)
        end
        map, count, cost = ContextClusterer.cluster(histograms, MAX_CLUSTERS)
        cost += count * 6.0 # context map entries and mode bits, roughly
        if cost < best_cost
          best_cost = cost
          best = {mode, map, count}
        end
      end
      best
    end

    # Stores a context map (RFC 7932, section 7.3): move-to-front, zero
    # runs as run-length codes, and the prefix code over both.
    def store_context_map(writer : BitWriter, map : Bytes, trees : Int32) : Nil
      ranks = move_to_front(map)
      longest = 0
      run = 0
      ranks.each do |rank|
        run = rank == 0 ? run + 1 : 0
        longest = run if run > longest
      end
      max_prefix = longest > 0 ? Math.min(MatchFinder.log2_floor(longest), 6) : 0
      symbols = [] of Int32
      extras = [] of Int32
      index = 0
      while index < ranks.size
        if ranks[index] != 0
          symbols << ranks[index] + max_prefix
          extras << 0
          index += 1
          next
        end
        repeats = 1
        while index + repeats < ranks.size && ranks[index + repeats] == 0
          repeats += 1
        end
        index += repeats
        while repeats > 0
          if repeats < (2 << max_prefix)
            prefix = MatchFinder.log2_floor(repeats)
            symbols << prefix
            extras << repeats - (1 << prefix)
            repeats = 0
          else
            symbols << max_prefix
            extras << (1 << max_prefix) - 1
            repeats -= (2 << max_prefix) - 1
          end
        end
      end
      alphabet = trees + max_prefix
      counts = Slice(UInt32).new(alphabet, 0_u32)
      symbols.each { |symbol| counts[symbol] += 1 }
      if max_prefix > 0
        writer.write(1, 1)
        writer.write(4, max_prefix - 1)
      else
        writer.write(1, 0)
      end
      code = @scratch_code
      code.build_and_store(writer, counts, alphabet)
      symbols.each_with_index do |symbol, at|
        code.write(writer, symbol)
        writer.write(symbol, extras[at]) if symbol > 0 && symbol <= max_prefix
      end
      writer.write(1, 1) # IMTF
    end

    private def move_to_front(map : Bytes) : Array(Int32)
      order = Array(Int32).new(256) { |value| value }
      map.to_a.map do |value|
        rank = order.index!(value.to_i32)
        order.delete_at(rank)
        order.unshift(value.to_i32)
        rank
      end
    end
  end

  # Writes one category's block switches: the header part (NBLTYPES and,
  # with more than one type, the type and count codes and the first
  # count) and each switch as the commands reach it.
  #
  # :nodoc:
  class BlockSwitchWriter
    @type_count : Int32
    @types : Array(Int32)
    @lengths : Array(Int32)
    @type_codes : Array(Int32)
    @type_code : HuffmanCode
    @count_code : HuffmanCode
    @block = 0
    @left : Int32

    def initialize(splitter : BlockSplitter)
      @type_count = splitter.type_count
      @types = splitter.types
      @lengths = splitter.lengths
      @type_code = HuffmanCode.new(@type_count + 2)
      @count_code = HuffmanCode.new(MetablockWriter::BLOCK_COUNT_CODES)
      @left = @type_count > 1 ? @lengths[0] : Int32::MAX
      # google/brotli starts the calculator at last 1, second last 0, so
      # after the first block the decoder ring (last 0, second last 1) agrees.
      last = 1
      second_last = 0
      @type_codes = @types.map do |type|
        code = type == last + 1 ? 1 : (type == second_last ? 0 : type + 2)
        second_last = last
        last = type
        code
      end
    end

    def store_header(writer : BitWriter) : Nil
      write_var_len(writer, @type_count - 1)
      return if @type_count == 1
      type_counts = Slice(UInt32).new(@type_count + 2, 0_u32)
      (1...@types.size).each { |block| type_counts[@type_codes[block]] += 1 }
      count_counts = Slice(UInt32).new(MetablockWriter::BLOCK_COUNT_CODES, 0_u32)
      @lengths.each { |length| count_counts[EncoderCodes.block_count_code(length)] += 1 }
      @type_code.build_and_store(writer, type_counts, @type_count + 2)
      @count_code.build_and_store(writer, count_counts, MetablockWriter::BLOCK_COUNT_CODES)
      write_count(writer, @lengths[0])
    end

    # The block type of the next symbol, writing a block switch first when
    # the current block is used up.
    @[AlwaysInline]
    def next_type(writer : BitWriter) : Int32
      if @left == 0
        @block += 1
        @type_code.write(writer, @type_codes[@block])
        @left = @lengths[@block]
        write_count(writer, @left)
      end
      @left -= 1
      @type_count > 1 ? @types.unsafe_fetch(@block) : 0
    end

    private def write_count(writer : BitWriter, length : Int32) : Nil
      code = EncoderCodes.block_count_code(length)
      @count_code.write(writer, code)
      writer.write(Decoder::BLOCK_LENGTH_EXTRA[code], length - Decoder::BLOCK_LENGTH_BASE[code])
    end

    private def write_var_len(writer : BitWriter, value : Int32) : Nil
      if value == 0
        writer.write(1, 0)
        return
      end
      bits = MatchFinder.log2_floor(value)
      writer.write(1, 1)
      writer.write(3, bits)
      writer.write(bits, value - (1 << bits))
    end
  end

  # Groups the 64 literal contexts into clusters: merges the pair whose
  # union costs least more than its parts until no merge saves bits and
  # at most *limit* clusters remain.
  #
  # :nodoc:
  module ContextClusterer
    # Returns {context to cluster map, cluster count, estimated bits}.
    def self.cluster(histograms : Array(Slice(UInt32)), limit : Int32) : {Bytes, Int32, Float64}
      members = [] of Array(Int32)
      sums = [] of Slice(UInt32)
      histograms.each_with_index do |histogram, context|
        next if histogram.all?(&.zero?)
        members << [context]
        sums << histogram.dup
      end
      map = Bytes.new(64, 0_u8)
      return {map, 1, 0.0} if sums.empty?
      costs = sums.map { |histogram| Entropy.population_cost(histogram) }
      count = sums.size
      alive = Array.new(count, true)
      delta = Array.new(count) { Array.new(count, 0.0) }
      count.times do |left|
        (left + 1...count).each do |right|
          delta[left][right] = union_cost(sums[left], sums[right]) - costs[left] - costs[right]
        end
      end
      clusters = count
      while clusters > 1
        best = Float64::MAX
        best_left = 0
        best_right = 0
        count.times do |left|
          next unless alive[left]
          (left + 1...count).each do |right|
            next unless alive[right]
            if delta[left][right] < best
              best = delta[left][right]
              best_left = left
              best_right = right
            end
          end
        end
        break if best >= 0 && clusters <= limit
        merged = Slice(UInt32).new(256) { |symbol| sums[best_left][symbol] + sums[best_right][symbol] }
        sums[best_left] = merged
        costs[best_left] = Entropy.population_cost(merged)
        members[best_left].concat(members[best_right])
        alive[best_right] = false
        clusters -= 1
        count.times do |other|
          next if other == best_left || !alive[other]
          left, right = other < best_left ? {other, best_left} : {best_left, other}
          delta[left][right] = union_cost(sums[left], sums[right]) - costs[left] - costs[right]
        end
      end
      live = (0...count).select { |index| alive[index] }
      live.each_with_index do |index, cluster|
        members[index].each { |context| map[context] = cluster.to_u8 }
      end
      {map, live.size, live.sum { |index| costs[index] }}
    end

    private def self.union_cost(left : Slice(UInt32), right : Slice(UInt32)) : Float64
      Entropy.population_cost(Slice(UInt32).new(256) { |symbol| left[symbol] + right[symbol] })
    end
  end
end
