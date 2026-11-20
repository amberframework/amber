require "../../spec_helper"

{% skip_file if flag?(:gc_none) %}

private def heap_mib : Int32
  (GC.stats.heap_size // Amber::Server::GrowHeapToStartingSize::BYTES_PER_MIB).to_i32
end

describe Amber::Server::GrowHeapToStartingSize do
  describe "#perform" do
    it "grows the heap to the starting size" do
      starting_heap_mib = heap_mib + 64
      grown_bytes = Amber::Server::GrowHeapToStartingSize.new(starting_heap_mib).perform

      grown_bytes.should be > 0
      GC.stats.heap_size.should be >= starting_heap_mib.to_u64 * Amber::Server::GrowHeapToStartingSize::BYTES_PER_MIB
    end

    it "leaves a heap that is already at least the starting size" do
      heap_bytes_before = GC.stats.heap_size
      Amber::Server::GrowHeapToStartingSize.new(heap_mib).perform.should eq 0
      GC.stats.heap_size.should eq heap_bytes_before
    end

    it "leaves the heap alone when no starting size is set" do
      heap_bytes_before = GC.stats.heap_size
      Amber::Server::GrowHeapToStartingSize.new(0).perform.should eq 0
      GC.stats.heap_size.should eq heap_bytes_before
    end
  end
end
