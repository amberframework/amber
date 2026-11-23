module Amber::Mica::Brotli::Encode
  # Scratch memory for one metablock at a time, outside the garbage
  # collector: histograms, block splits, context maps and code tables are
  # bumped out of a few large chunks and all dropped at once with `reset`,
  # so encoding allocates almost nothing the collector has to track.
  class Arena
    CHUNK_BYTES = 64 * 1024
    ALIGNMENT   = 16

    @chunks = [] of {Pointer(UInt8), Int32}
    @current = 0
    @offset = 0

    def finalize
      release
    end

    # *count* uncleared values of *type*, valid until `reset`.
    def alloc(type : T.class, count : Int32) : Pointer(T) forall T
      bytes = (Math.max(count, 1) &* sizeof(T) &+ (ALIGNMENT - 1)) & ~(ALIGNMENT - 1)
      while @current < @chunks.size
        base, size = @chunks[@current]
        if @offset &+ bytes <= size
          memory = base + @offset
          @offset &+= bytes
          return memory.as(Pointer(T))
        end
        @current &+= 1
        @offset = 0
      end
      size = Math.max(CHUNK_BYTES, bytes)
      @chunks << {Encode.table(UInt8, size), size}
      @current = @chunks.size &- 1
      @offset = bytes
      @chunks[@current][0].as(Pointer(T))
    end

    # *count* zeroed values of *type*, valid until `reset`.
    def alloc_cleared(type : T.class, count : Int32) : Pointer(T) forall T
      memory = alloc(type, count)
      memory.clear(count)
      memory
    end

    # Makes all the memory handed out available again.
    def reset : Nil
      @current = 0
      @offset = 0
    end

    # Frees the chunks.
    def release : Nil
      @chunks.each { |chunk| Encode.free_table(chunk[0]) }
      @chunks.clear
      reset
    end
  end
end
