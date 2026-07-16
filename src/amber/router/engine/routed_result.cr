require "uri"

module Amber::Router
  class RoutedResult(T)
    include Comparable(RoutedResult)

    @params : Hash(String, String)?
    @param_key : String?
    @param_value : String?
    @param_source : String?
    @param_byte_offset : Int32
    @param_bytesize : Int32
    @param_collapse_slashes : Bool

    def initialize(@terminal_segment : TerminalSegment(T)?)
      @param_byte_offset = 0
      @param_bytesize = 0
      @param_collapse_slashes = false
    end

    def params : Hash(String, String)
      @params ||= begin
        materialized = {} of String => String
        if key = @param_key
          materialized[key] = first_param_value
        end
        materialized
      end
    end

    def []?(key : String) : String?
      if materialized = @params
        materialized[key]?
      elsif @param_key == key
        first_param_value
      end
    end

    def [](key : String) : String
      params[key]
    end

    def []=(key : String, value : String) : String
      if materialized = @params
        materialized[key] = value
      elsif stored_key = @param_key
        if stored_key == key
          @param_value = value
          @param_source = nil
        else
          params[key] = value
        end
      else
        @param_key = key
        @param_value = value
      end

      value
    end

    def capture(key : String, source : String, byte_offset : Int32, bytesize : Int32, *, collapse_slashes = false) : Nil
      if materialized = @params
        materialized[key] = decode_span(source, byte_offset, bytesize, collapse_slashes)
      elsif stored_key = @param_key
        if stored_key == key
          store_span(source, byte_offset, bytesize, collapse_slashes)
        else
          params[key] = decode_span(source, byte_offset, bytesize, collapse_slashes)
        end
      else
        @param_key = key
        store_span(source, byte_offset, bytesize, collapse_slashes)
      end
    end

    def terminal_segment
      @terminal_segment.not_nil!
    end

    def path
      if found?
        terminal_segment.full_path
      else
        raise "Cannot provide route path when no route was found. Ask first with #found?"
      end
    end

    def found?
      !@terminal_segment.nil?
    end

    def payload?
      terminal_segment.route if found?
    end

    def payload
      payload?
    end

    def priority
      if found?
        terminal_segment.priority
      else
        -1
      end
    end

    def <=>(other : RoutedResult)
      priority <=> other.priority
    end

    def formatted_s(io : IO)
      io << "#<RoutedResult "

      if found?
        io << "found "
        io << terminal_segment.full_path
      else
        io << "not found"
      end
      io << '>'
    end

    private def store_span(source : String, byte_offset : Int32, bytesize : Int32, collapse_slashes : Bool) : Nil
      @param_value = nil
      @param_source = source
      @param_byte_offset = byte_offset
      @param_bytesize = bytesize
      @param_collapse_slashes = collapse_slashes
    end

    private def first_param_value : String
      @param_value ||= begin
        source = @param_source.not_nil!
        decode_span(source, @param_byte_offset, @param_bytesize, @param_collapse_slashes)
      end
    end

    private def decode_span(source : String, byte_offset : Int32, bytesize : Int32, collapse_slashes = false) : String
      value = collapse_slashes ? collapsed_span(source, byte_offset, bytesize) : source.byte_slice(byte_offset, bytesize)
      value.includes?('%') ? URI.decode(value) : value
    end

    private def collapsed_span(source : String, byte_offset : Int32, bytesize : Int32) : String
      segment_end = byte_offset + bytesize
      previous_slash = false

      String.build(bytesize) do |io|
        index = byte_offset
        while index < segment_end
          byte = source.byte_at(index)
          slash = byte == '/'.ord
          io.write_byte(byte) unless slash && previous_slash
          previous_slash = slash
          index += 1
        end
      end
    end
  end
end
