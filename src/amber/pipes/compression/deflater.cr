{% unless flag?(:without_zlib) %}
  require "compress/deflate"

  module Amber
    module Pipe
      class Compression < Base
        # One raw DEFLATE stream whose zlib state and output buffer live
        # outside the garbage-collected heap, so it can compress one response
        # after another without allocating.
        #
        # It uses the settings `Compress::Deflate::Writer` uses (raw DEFLATE,
        # 15 window bits, memory level 8, the default strategy), so its output
        # is byte for byte the same.
        #
        # :nodoc:
        class Deflater
          OUTPUT_BUFFER_BYTES = 8192

          @stream : LibZ::ZStream
          @output_buffer : UInt8*
          @released = false

          def initialize(@level : Int32)
            # Leaving `zalloc` and `zfree` null makes zlib use `malloc` and
            # `free`, outside the collected heap.
            @stream = LibZ::ZStream.new
            result = LibZ.deflateInit2(pointerof(@stream), @level, LibZ::Z_DEFLATED, -LibZ::MAX_BITS,
              LibZ::DEF_MEM_LEVEL, ::Compress::Deflate::Strategy::DEFAULT.value, LibZ.zlibVersion,
              sizeof(LibZ::ZStream))
            raise ::Compress::Deflate::Error.new(result, @stream) unless result.ok?
            @output_buffer = LibC.malloc(OUTPUT_BUFFER_BYTES).as(UInt8*)
            raise RuntimeError.new("Could not allocate the compression buffer") if @output_buffer.null?
          end

          # Compresses *slice* into *output*, keeping zlib's own buffering.
          def write(slice : Bytes, output : IO) : Nil
            return if slice.empty?
            @stream.avail_in = slice.size
            @stream.next_in = slice.to_unsafe
            consume_output(LibZ::Flush::NO_FLUSH, output)
          end

          # Writes everything compressed so far, ending on a byte boundary.
          def flush(output : IO) : Nil
            consume_output(LibZ::Flush::SYNC_FLUSH, output)
          end

          # Ends the stream and writes its last bytes.
          def finish(output : IO) : Nil
            @stream.avail_in = 0
            @stream.next_in = Pointer(UInt8).null
            consume_output(LibZ::Flush::FINISH, output)
          end

          # Readies the stream for the next response, keeping its memory.
          def reset : Nil
            result = LibZ.deflateReset(pointerof(@stream))
            raise ::Compress::Deflate::Error.new(result, @stream) unless result.ok?
          end

          # Frees the zlib state and the output buffer.
          def release : Nil
            return if @released
            @released = true
            LibZ.deflateEnd(pointerof(@stream))
            LibC.free(@output_buffer.as(Void*))
          end

          # A compressor dropped without `#release` (a response that never
          # closed) still frees its memory when it is collected.
          def finalize
            release
          end

          private def consume_output(flush : LibZ::Flush, output : IO) : Nil
            loop do
              @stream.next_out = @output_buffer
              @stream.avail_out = OUTPUT_BUFFER_BYTES.to_u32
              LibZ.deflate(pointerof(@stream), flush)
              written = OUTPUT_BUFFER_BYTES - @stream.avail_out
              output.write(Slice.new(@output_buffer, written)) if written > 0
              break if @stream.avail_out != 0
            end
          end
        end

        # Keeps up to *idle_limit* compressors between responses. Safe to
        # share across fibers and threads.
        #
        # :nodoc:
        class DeflaterPool
          getter level : Int32
          getter idle_limit : Int32

          def initialize(@level : Int32, @idle_limit : Int32)
            @idle = Array(Deflater).new(@idle_limit)
            @mutex = Mutex.new
          end

          # How many compressors wait in the pool now.
          def idle_count : Int32
            @mutex.synchronize { @idle.size }
          end

          def checkout : Deflater
            @mutex.synchronize { @idle.pop? } || Deflater.new(@level)
          end

          # Takes back *deflater* after its response ends. One that cannot be
          # reset, or that does not fit, is freed now.
          def checkin(deflater : Deflater) : Nil
            begin
              deflater.reset
            rescue ::Compress::Deflate::Error
              deflater.release
              return
            end
            kept = @mutex.synchronize do
              if @idle.size < @idle_limit
                @idle << deflater
                true
              else
                false
              end
            end
            deflater.release unless kept
          end
        end
      end
    end
  end
{% end %}
