{% unless flag?(:gc_none) %}
  # The one Boehm GC call Amber makes that Crystal's `LibGC` does not bind.
  # `GC_expand_hp` is part of bdwgc's public API (`gc.h`) on every platform
  # Crystal supports; libgc is already linked by the runtime.
  lib LibAmberGC
    # Grows the collector's heap by *bytes*, rounded up to whole heap blocks.
    # Returns 0 when the memory could not be obtained.
    fun expand_hp = GC_expand_hp(bytes : LibC::SizeT) : LibC::Int
  end
{% end %}

module Amber
  class Server
    # Grows the garbage collector's heap to the starting size an app sets in
    # `server.gc_initial_heap_mib`, before the server takes its first request.
    #
    # Boehm GC starts with a heap of a few hundred KiB and decides how often
    # to collect from the heap it has, so a server that starts small collects
    # often under load until the heap has grown. A starting heap of a few tens
    # of MiB removes that early collection cost; memory the program never
    # touches is reserved address space, not resident memory.
    #
    # It only grows the heap: a heap that is already at least that large, for
    # example because `GC_INITIAL_HEAP_SIZE` was set, is left as it is.
    #
    # ```
    # Amber::Server::GrowHeapToStartingSize.new(starting_heap_mib: 32).perform
    # GC.stats.heap_size # => at least 33_554_432
    # ```
    struct GrowHeapToStartingSize
      BYTES_PER_MIB = 1_048_576_u64

      getter starting_heap_mib : Int32

      def initialize(@starting_heap_mib : Int32)
      end

      # Returns how many bytes the heap grew by. That is 0 when no starting
      # size is set, when the heap is already that large, when the program is
      # built without a collector (`-Dgc_none`), and when the collector could
      # not obtain the memory, which is logged as a warning.
      def perform : UInt64
        return 0_u64 unless starting_heap_mib > 0

        {% if flag?(:gc_none) %}
          0_u64
        {% else %}
          starting_heap_bytes = starting_heap_mib.to_u64 * BYTES_PER_MIB
          heap_bytes_before = GC.stats.heap_size
          return 0_u64 if heap_bytes_before >= starting_heap_bytes

          missing_bytes = starting_heap_bytes - heap_bytes_before
          if LibAmberGC.expand_hp(LibC::SizeT.new(missing_bytes)) == 0
            Log.warn { "Could not grow the garbage collector's heap to #{starting_heap_mib} MiB (server.gc_initial_heap_mib); continuing with #{heap_bytes_before // BYTES_PER_MIB} MiB" }
            return 0_u64
          end

          grown_bytes = GC.stats.heap_size - heap_bytes_before
          Log.debug { "Garbage collector heap starts at #{GC.stats.heap_size // BYTES_PER_MIB} MiB (server.gc_initial_heap_mib: #{starting_heap_mib})" }
          grown_bytes
        {% end %}
      end
    end
  end
end
